#!/usr/bin/env python3
"""
test_export.py - Validate Enchanted export format

Tests that an export file matches the expected schema and can be imported.
"""

import json
import sys
from pathlib import Path
from datetime import datetime


def validate_iso8601(date_string):
    """Check if string is valid ISO8601"""
    try:
        datetime.fromisoformat(date_string.replace('Z', '+00:00'))
        return True
    except:
        return False


def validate_message(msg, conv_id):
    """Validate a single message"""
    errors = []
    
    # Required fields
    if 'role' not in msg:
        errors.append(f"  Message missing 'role'")
    if 'content' not in msg:
        errors.append(f"  Message missing 'content'")
    
    # Check types
    if 'role' in msg and not isinstance(msg['role'], str):
        errors.append(f"  Message 'role' should be string, got {type(msg['role'])}")
    if 'content' in msg and not isinstance(msg['content'], str):
        errors.append(f"  Message 'content' should be string, got {type(msg['content'])}")
    
    # Optional timestamp validation
    if 'timestamp' in msg and msg['timestamp'] is not None:
        if not validate_iso8601(msg['timestamp']):
            errors.append(f"  Invalid timestamp format: {msg['timestamp']}")
    
    return errors


def validate_conversation(conv, index):
    """Validate a single conversation"""
    errors = []
    prefix = f"Conversation {index}"
    
    # Required fields
    required = ['platformId', 'createdAt', 'updatedAt', 'messageCount', 'messages']
    for field in required:
        if field not in conv:
            errors.append(f"{prefix}: Missing required field '{field}'")
    
    # UUID format check (basic)
    if 'platformId' in conv:
        platform_id = conv['platformId']
        if not isinstance(platform_id, str) or len(platform_id) != 36:
            errors.append(f"{prefix}: platformId should be UUID string")
    
    # Timestamp validation
    if 'createdAt' in conv and not validate_iso8601(conv['createdAt']):
        errors.append(f"{prefix}: Invalid createdAt timestamp")
    if 'updatedAt' in conv and not validate_iso8601(conv['updatedAt']):
        errors.append(f"{prefix}: Invalid updatedAt timestamp")
    
    # Message count should match
    if 'messageCount' in conv and 'messages' in conv:
        if conv['messageCount'] != len(conv['messages']):
            errors.append(f"{prefix}: messageCount ({conv['messageCount']}) != len(messages) ({len(conv['messages'])})")
    
    # Validate messages
    if 'messages' in conv:
        for msg_idx, msg in enumerate(conv['messages']):
            msg_errors = validate_message(msg, conv.get('platformId', 'unknown'))
            if msg_errors:
                errors.append(f"{prefix}, Message {msg_idx}:")
                errors.extend(msg_errors)
    
    return errors


def validate_export(data):
    """Validate entire export structure"""
    errors = []
    warnings = []
    
    # Root structure
    if not isinstance(data, dict):
        errors.append("Export should be a JSON object")
        return errors, warnings
    
    # Required root fields
    if 'exportDate' not in data:
        errors.append("Missing 'exportDate' at root")
    elif not validate_iso8601(data['exportDate']):
        errors.append(f"Invalid exportDate format: {data['exportDate']}")
    
    if 'exportVersion' not in data:
        warnings.append("Missing 'exportVersion' (recommended)")
    
    if 'conversations' not in data:
        errors.append("Missing 'conversations' array")
        return errors, warnings
    
    conversations = data['conversations']
    if not isinstance(conversations, list):
        errors.append("'conversations' should be an array")
        return errors, warnings
    
    # Validate each conversation
    for idx, conv in enumerate(conversations):
        conv_errors = validate_conversation(conv, idx)
        errors.extend(conv_errors)
    
    return errors, warnings


def print_stats(data):
    """Print export statistics"""
    conversations = data.get('conversations', [])
    total_messages = sum(c.get('messageCount', 0) for c in conversations)
    agent_convs = sum(1 for c in conversations if c.get('agentId'))
    model_convs = len(conversations) - agent_convs
    
    print(f"\n📊 Export Statistics:")
    print(f"  Export date: {data.get('exportDate', 'N/A')}")
    print(f"  Export version: {data.get('exportVersion', 'N/A')}")
    print(f"  Total conversations: {len(conversations)}")
    print(f"  Agent conversations: {agent_convs}")
    print(f"  Model conversations: {model_convs}")
    print(f"  Total messages: {total_messages}")
    
    if conversations:
        avg_messages = total_messages / len(conversations)
        print(f"  Average messages per conversation: {avg_messages:.1f}")
        
        # Find longest conversation
        longest = max(conversations, key=lambda c: c.get('messageCount', 0))
        print(f"  Longest conversation: {longest.get('messageCount', 0)} messages")
        
        # Count by model
        models = {}
        for conv in conversations:
            model = conv.get('model', 'unknown')
            models[model] = models.get(model, 0) + 1
        
        print(f"\n  Models used:")
        for model, count in sorted(models.items(), key=lambda x: -x[1])[:5]:
            print(f"    {model}: {count}")


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 test_export.py <export.json>")
        print("Example: python3 test_export.py enchanted-export-1720425600.json")
        sys.exit(1)
    
    path = Path(sys.argv[1])
    
    if not path.exists():
        print(f"❌ File not found: {path}")
        sys.exit(1)
    
    print(f"Validating export: {path}")
    print("=" * 60)
    
    # Load JSON
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON: {e}")
        sys.exit(1)
    
    # Validate
    errors, warnings = validate_export(data)
    
    # Report results
    if errors:
        print(f"\n❌ Found {len(errors)} errors:")
        for error in errors[:10]:  # Limit to first 10
            print(f"  - {error}")
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more")
        sys.exit(1)
    
    if warnings:
        print(f"\n⚠️  Found {len(warnings)} warnings:")
        for warning in warnings:
            print(f"  - {warning}")
    
    print("\n✅ Export format is valid!")
    
    # Print statistics
    print_stats(data)
    
    # Check if import script exists
    import_script = Path(__file__).parent / "import_enchanted.py"
    if import_script.exists():
        print(f"\n💡 Next step:")
        print(f"  python3 import_enchanted.py {path.name} enchanted.json")


if __name__ == '__main__':
    main()
