//
//  SecureChannelRoundTripTests.swift
//
//  Local round-trip tests for the vendored Osaurus Secure Channel.
//  No network, no live Osaurus instance: the vendored SecureChannel.swift
//  contains BOTH protocol halves, so we play server and client in-process.
//
//  ⚠️ Adjust the @testable import to your app module name (e.g. Enchanted).
//

import CryptoKit
import P256K
import XCTest

@testable import Enchanted  // ← change to your module name

final class SecureChannelRoundTripTests: XCTestCase {

    // MARK: - Test Identity

    /// A random secp256k1 "agent key" playing the server, plus its derived
    /// 0x… address — the thing a real client pins at discovery time.
    private func makeServerIdentity() throws -> (privateKey: Data, address: String) {
        var raw = Data(count: 32)
        repeat {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            raw = Data(bytes)
        } while (try? P256K.Recovery.PrivateKey(dataRepresentation: raw)) == nil
        let address = try deriveOsaurusId(from: raw)
        return (raw, address)
    }

    /// Perform a full in-process handshake; returns both established sessions.
    private func handshake() throws -> (
        client: SecureChannelSession, server: SecureChannelSession, address: String
    ) {
        let identity = try makeServerIdentity()
        let (ephemeralKey, hello) = SecureChannel.makeClientHello(agentAddress: identity.address)
        let (serverSession, serverHello) = try SecureChannel.establishServerSession(hello: hello) {
            transcript in
            try signSecureChannelPayload(transcript, privateKey: identity.privateKey)
        }
        let clientSession = try SecureChannel.establishClientSession(
            hello: hello,
            ephemeralKey: ephemeralKey,
            serverHello: serverHello,
            expectedAgentAddress: identity.address
        )
        return (clientSession, serverSession, identity.address)
    }

    // MARK: - Handshake

    func testHandshakeDerivesMatchingKeys() throws {
        let (client, server, _) = try handshake()
        XCTAssertEqual(client.sid, server.sid)

        // Matching keys are proven by a call surviving the round trip.
        let inner = Data("hello, agent".utf8)
        let (call, _) = try client.sealCall(innerRequest: inner)
        let (opened, _) = try server.openCall(call)
        XCTAssertEqual(opened, inner)
    }

    func testHandshakeRejectsWrongPinnedAddress() throws {
        let identity = try makeServerIdentity()
        let impostor = try makeServerIdentity()  // different key, different address
        let (ephemeralKey, hello) = SecureChannel.makeClientHello(agentAddress: identity.address)
        let (_, serverHello) = try SecureChannel.establishServerSession(hello: hello) { transcript in
            try signSecureChannelPayload(transcript, privateKey: identity.privateKey)
        }
        XCTAssertThrowsError(
            try SecureChannel.establishClientSession(
                hello: hello,
                ephemeralKey: ephemeralKey,
                serverHello: serverHello,
                expectedAgentAddress: impostor.address  // pinned the wrong peer
            )
        ) { error in
            XCTAssertEqual(error as? SecureChannelError, .identityMismatch)
        }
    }

    func testHandshakeRejectsTamperedTranscript() throws {
        let identity = try makeServerIdentity()
        let (ephemeralKey, hello) = SecureChannel.makeClientHello(agentAddress: identity.address)
        let (_, serverHello) = try SecureChannel.establishServerSession(hello: hello) { transcript in
            try signSecureChannelPayload(transcript, privateKey: identity.privateKey)
        }
        // A MITM substitutes its own ephemeral key but cannot re-sign.
        let mitmKey = Curve25519.KeyAgreement.PrivateKey()
        let tampered = SecureChannel.ServerHello(
            v: serverHello.v,
            sid: serverHello.sid,
            encPub: mitmKey.publicKey.rawRepresentation.base64urlEncoded,
            expiresAt: serverHello.expiresAt,
            signature: serverHello.signature
        )
        XCTAssertThrowsError(
            try SecureChannel.establishClientSession(
                hello: hello,
                ephemeralKey: ephemeralKey,
                serverHello: tampered,
                expectedAgentAddress: identity.address
            )
        ) { error in
            XCTAssertEqual(error as? SecureChannelError, .identityMismatch)
        }
    }

    // MARK: - Calls and Anti-Replay

    func testReplayedCallIsRejected() throws {
        let (client, server, _) = try handshake()
        let (call, _) = try client.sealCall(innerRequest: Data("once".utf8))
        _ = try server.openCall(call)
        XCTAssertThrowsError(try server.openCall(call)) { error in
            XCTAssertEqual(error as? SecureChannelError, .replayedFrame)
        }
    }

    func testInnerRequestSurvivesRoundTrip() throws {
        let (client, server, _) = try handshake()
        let inner = SecureChannel.InnerRequest(
            method: "POST",
            path: "/agents/0xabc123/run",
            authorization: "Bearer osk-v1.test-key",
            accept: "text/event-stream",
            contentType: "application/json",
            headers: ["X-Custom": "value"],
            body: Data(#"{"messages":[]}"#.utf8).base64urlEncoded
        )
        let (call, _) = try client.sealCall(innerRequest: try JSONEncoder().encode(inner))
        let (plaintext, _) = try server.openCall(call)
        let decoded = try JSONDecoder().decode(SecureChannel.InnerRequest.self, from: plaintext)
        XCTAssertEqual(decoded, inner)
    }

    // MARK: - Buffered Response

    func testBufferedResponseRoundTrip() throws {
        let (client, server, _) = try handshake()
        let (call, requestSeq) = try client.sealCall(innerRequest: Data("req".utf8))
        _ = try server.openCall(call)

        let innerResponse = SecureChannel.InnerResponse(
            status: 200,
            contentType: "application/json",
            body: Data(#"{"ok":true}"#.utf8).base64urlEncoded
        )
        let sealer = server.makeResponseSealer(requestSeq: requestSeq)
        let frame = try sealer.seal(try JSONEncoder().encode(innerResponse), fin: true)

        let opener = client.makeResponseOpener(requestSeq: requestSeq)
        let opened = try SecureChannelClient.openBufferedResponse(
            try JSONEncoder().encode(frame),
            opener: opener
        )
        XCTAssertEqual(opened, innerResponse)
    }

    // MARK: - Streaming (SSE)

    /// Wrap frames the way the server does on the wire: `data: {json}\n\n`.
    private func sseBytes(for frames: [SecureChannel.Frame]) throws -> Data {
        var out = Data()
        for frame in frames {
            out.append(Data("data: ".utf8))
            out.append(try JSONEncoder().encode(frame))
            out.append(Data("\n\n".utf8))
        }
        return out
    }

    func testStreamedResponseRoundTripAcrossChunkBoundaries() throws {
        let (client, server, _) = try handshake()
        let (call, requestSeq) = try client.sealCall(innerRequest: Data("req".utf8))
        _ = try server.openCall(call)

        // The plaintext of the stream is the ORIGINAL SSE the agent produced —
        // the decoder's output feeds an unmodified SSE parser downstream.
        let originalSSE = [
            "data: {\"delta\":\"Hel\"}\n\n",
            "data: {\"delta\":\"lo\"}\n\n",
            "data: [DONE]\n\n",
        ]
        let sealer = server.makeResponseSealer(requestSeq: requestSeq)
        var frames = try originalSSE.map { try sealer.seal(Data($0.utf8)) }
        frames.append(try sealer.seal(Data(), fin: true))

        let outerBytes = try sseBytes(for: frames)
        let opener = client.makeResponseOpener(requestSeq: requestSeq)
        let decoder = SecureFrameStreamDecoder(opener: opener)

        // Feed in awkward chunk sizes to exercise the internal buffer.
        var plaintext = Data()
        var index = outerBytes.startIndex
        let chunkSizes = [1, 7, 64, 3, 1024]
        var chunkIndex = 0
        while index < outerBytes.endIndex {
            let size = chunkSizes[chunkIndex % chunkSizes.count]
            chunkIndex += 1
            let end = outerBytes.index(index, offsetBy: size, limitedBy: outerBytes.endIndex)
                ?? outerBytes.endIndex
            plaintext.append(try decoder.feed(outerBytes.subdata(in: index ..< end)))
            index = end
        }

        XCTAssertNoThrow(try decoder.verifyCompleted())
        XCTAssertEqual(String(decoding: plaintext, as: UTF8.self), originalSSE.joined())
    }

    func testTruncatedStreamIsDetected() throws {
        let (client, server, _) = try handshake()
        let (call, requestSeq) = try client.sealCall(innerRequest: Data("req".utf8))
        _ = try server.openCall(call)

        let sealer = server.makeResponseSealer(requestSeq: requestSeq)
        // Two content frames, NO fin — a relay/middlebox cut the connection.
        let frames = [
            try sealer.seal(Data("data: {\"delta\":\"Hel\"}\n\n".utf8)),
            try sealer.seal(Data("data: {\"delta\":\"lo\"}\n\n".utf8)),
        ]

        let opener = client.makeResponseOpener(requestSeq: requestSeq)
        let decoder = SecureFrameStreamDecoder(opener: opener)
        _ = try decoder.feed(try sseBytes(for: frames))

        XCTAssertThrowsError(try decoder.verifyCompleted()) { error in
            XCTAssertEqual(error as? SecureChannelClientError, .streamTruncated)
        }
    }

    func testOutOfOrderFrameIsRejected() throws {
        let (client, server, _) = try handshake()
        let (call, requestSeq) = try client.sealCall(innerRequest: Data("req".utf8))
        _ = try server.openCall(call)

        let sealer = server.makeResponseSealer(requestSeq: requestSeq)
        let frame0 = try sealer.seal(Data("a".utf8))
        let frame1 = try sealer.seal(Data("b".utf8))

        let opener = client.makeResponseOpener(requestSeq: requestSeq)
        // Deliver frame 1 before frame 0.
        XCTAssertThrowsError(try opener.open(frame1)) { error in
            XCTAssertEqual(error as? SecureChannelError, .outOfOrderFrame)
        }
        // In-order delivery still works after the rejected attempt.
        XCTAssertEqual(try opener.open(frame0).plaintext, Data("a".utf8))
    }

    func testResponseFramesCannotCrossCalls() throws {
        let (client, server, _) = try handshake()

        let (call1, seq1) = try client.sealCall(innerRequest: Data("one".utf8))
        _ = try server.openCall(call1)
        let (call2, seq2) = try client.sealCall(innerRequest: Data("two".utf8))
        _ = try server.openCall(call2)

        // Seal a frame for call 1, try to open it with call 2's opener.
        let frame = try server.makeResponseSealer(requestSeq: seq1)
            .seal(Data("secret".utf8), fin: true)
        let wrongOpener = client.makeResponseOpener(requestSeq: seq2)
        XCTAssertThrowsError(try wrongOpener.open(frame))
    }
}
