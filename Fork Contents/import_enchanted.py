#!/usr/bin/env python3
"""
import_enchanted.py - Import Enchanted iOS app exports into the KB

Usage:
    python3 import_enchanted.py enchanted-export-12345.json output.json
    
Output format matches the KB's normalized schema (see kb-architecture-v3.md).
"""

import json
import sys
import uuid
from datetime import datetime
from pathlib import Path


def generate_conversation_id(source: str, platform_id: str) -> str:
    """Generate deterministic UUIDv5 for a conversation"""
    namespace = uuid.UUID('00000000-0000-0000-0000-000000000000')
    seed = f"{source}:{platform_id}"
    return str(uuid.uuid5(namespace, seed))


def normalize_message(msg: dict) -> dict:
    """Normalize a message to KB schema"""
    # Handle image annotations
    content = msg['content']
    if msg.get('hasImage'):
        content = "[image attached]\n" + content
    
    return {
        'role': msg['role'],
        'content': content,
        'timestamp': msg.get('timestamp')
    }


def import_enchanted_export(input_path: Path, output_path: Path):
    """Import Enchanted export JSON and convert to KB normalized format"""
    
    with open(input_path, 'r', encoding='utf-8') as f:
        export_data = json.load(f)
    
    conversations = export_data.get('conversations', [])
    
    print(f"Processing {len(conversations)} conversations...")
    
    normalized = []
    
    for conv in conversations:
        platform_id = conv['platformId']
        conversation_id = generate_conversation_id('enchanted', platform_id)
        
        # Build metadata
        meta = {
            'export_version': export_data.get('exportVersion'),
            'export_date': export_data.get('exportDate')
        }
        
        # Add agent_id if present
        if conv.get('agentId'):
            meta['agent_id'] = conv['agentId']
        
        # Normalize messages
        messages = [normalize_message(msg) for msg in conv.get('messages', [])]
        
        normalized_conv = {
            'id': conversation_id,
            'source': 'enchanted',
            'platform_id': platform_id,
            'title': conv.get('title'),
            'created_at': conv['createdAt'],
            'updated_at': conv['updatedAt'],
            'model': conv.get('model'),
            'message_count': conv['messageCount'],
            'messages': messages,
            'raw_path': str(input_path.absolute()),
            'meta': meta
        }
        
        normalized.append(normalized_conv)
    
    # Write output
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(normalized, f, indent=2, ensure_ascii=False)
    
    print(f"✓ Wrote {len(normalized)} conversations to {output_path}")
    print(f"  Agent conversations: {sum(1 for c in normalized if 'agent_id' in c.get('meta', {}))}")
    print(f"  Model conversations: {sum(1 for c in normalized if 'agent_id' not in c.get('meta', {}))}")


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 import_enchanted.py <input.json> <output.json>")
        print("Example: python3 import_enchanted.py enchanted-export-1720425600.json enchanted.json")
        sys.exit(1)
    
    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    
    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}")
        sys.exit(1)
    
    try:
        import_enchanted_export(input_path, output_path)
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
