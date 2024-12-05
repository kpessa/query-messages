import sqlite3
import os
import pyperclip
import re
from datetime import datetime

def get_available_chats():
    """Get list of available chat conversations"""
    chat_db_path = os.path.expanduser("~/Library/Messages/chat.db")
    
    try:
        conn = sqlite3.connect(chat_db_path)
        cursor = conn.cursor()
        
        query = """
        SELECT 
            handle.id,
            COUNT(message.ROWID) as message_count
        FROM handle
        JOIN message ON message.handle_id = handle.ROWID
        GROUP BY handle.id
        ORDER BY message_count DESC
        LIMIT 20
        """
        
        cursor.execute(query)
        chats = cursor.fetchall()
        
        # Add contact names where available
        enhanced_chats = []
        for chat in chats:
            contact_id, count = chat
            contact_name = get_contact_info(contact_id)
            if contact_name:
                enhanced_chats.append((contact_id, count, contact_name))
            else:
                enhanced_chats.append((contact_id, count, None))
                
        return enhanced_chats
        
    finally:
        if 'conn' in locals():
            conn.close()

def decode_binary_attributed_body(data):
    """Extract text from binary attributed body data"""
    try:
        if not data:
            return None
            
        # Find the content between NSString marker and the terminator
        marker = b'NSString\x01\x94\x84\x01+'
        start = data.find(marker)
        if start > -1:
            start += len(marker)  # Skip past the marker
            
            # First byte after marker is length
            length = data[start]
            content = data[start + 1:start + 1 + length]
            
            # Only return the actual message content, strip any trailing binary data
            text = content.decode('utf-8', errors='replace')
            # Remove any binary data that might have been included
            text = text.split('\x00')[0]
            return text.strip()
            
    except Exception as e:
        print(f"DEBUG - Text extraction error: {str(e)}")
        print(f"DEBUG - Data slice: {data[:100]}")
    return None

def parse_reaction_type(text):
    """Parse reaction text into human-readable format"""
    if not text:
        return None
        
    # Common reaction patterns
    reactions = {
        'Loved ': 'Loved',
        'Liked ': 'Liked',
        'Emphasized ': 'Emphasized',
        'Laughed at ': 'Laughed at',
        'Disliked ': 'Disliked',
        'Questioned ': 'Questioned'
    }
    
    for pattern, reaction in reactions.items():
        if text.startswith(pattern):
            return reaction
    return '[reaction]'

def query_messages(contact_id, limit=None):
    """Query messages for a specific contact"""
    chat_db_path = os.path.expanduser("~/Library/Messages/chat.db")
    
    try:
        conn = sqlite3.connect(chat_db_path)
        cursor = conn.cursor()
        
        contact_name = get_contact_info(contact_id) or contact_id
        
        # Main query with explicit date handling
        base_query = """
        SELECT
            m.rowid as message_id,
            datetime(m.date/1000000000 + strftime('%s', '2001-01-01'), 'unixepoch', 'localtime') as message_date,
            CASE m.is_from_me WHEN 1 THEN 'me' ELSE ? END as sender,
            m.text,
            m.attributedBody,
            m.associated_message_type as msg_type,
            m.cache_has_attachments as has_attachments,
            m.is_from_me,
            m.guid,
            m.associated_message_guid
        FROM message m
        JOIN chat_message_join cmj ON m.rowid = cmj.message_id
        JOIN chat c ON cmj.chat_id = c.rowid
        LEFT JOIN handle h ON m.handle_id = h.rowid
        WHERE c.chat_identifier LIKE ?
        AND m.date > 0  -- Ensure valid dates
        ORDER BY m.date ASC
        """
        
        if limit is not None:
            cursor.execute(base_query + " LIMIT ?", (contact_name, f"%{contact_id}", limit))
        else:
            cursor.execute(base_query, (contact_name, f"%{contact_id}"))
                
        messages = cursor.fetchall()
        message_dict = {}  # Store messages by GUID
        reactions_dict = {}  # Store reactions by associated message GUID
        meaningful_messages = []
        
        print(f"\nProcessing {len(messages)} messages...")
        
        # First pass: organize messages and reactions
        for msg in messages:
            message_id, date, sender, text, attr_body, msg_type, has_attachments, is_from_me, guid, associated_guid = msg
            
            # Handle reactions (type 2000)
            if msg_type == 2000 and associated_guid:
                if associated_guid in reactions_dict:
                    reactions_dict[associated_guid].append({
                        'sender': sender,
                        'text': text,
                        'timestamp': date
                    })
                else:
                    reactions_dict[associated_guid] = [{
                        'sender': sender,
                        'text': text,
                        'timestamp': date
                    }]
                continue
            
            # Extract message content
            content = None
            if text:
                content = text
            elif attr_body:
                content = decode_binary_attributed_body(attr_body)
                
            if content or has_attachments == 1:
                message_entry = {
                    'timestamp': date,
                    'sender': sender,
                    'content': content if content else '[Media Attachment]',
                    'reactions': reactions_dict.get(guid, [])
                }
                meaningful_messages.append(message_entry)
                message_dict[guid] = message_entry
        
        # Format output
        clipboard_content = [f"{contact_name}\n{'-' * 50}"]
        
        for msg in meaningful_messages:
            # Format message line
            if msg['sender'] == 'me':
                message_line = f"{msg['timestamp']} to {contact_name} - Delivered"
            else:
                message_line = f"{msg['timestamp']} from {contact_name} - Read"
            
            clipboard_content.extend([
                "",  # Empty line
                message_line,
                "",  # Empty line
                msg['content'],
                "",  # Empty line
            ])
            
            # Add reactions if any exist
            if msg['reactions']:
                for reaction in sorted(msg['reactions'], key=lambda x: x['timestamp']):
                    reaction_text = parse_reaction_type(reaction['text'])
                    if reaction_text:
                        clipboard_content.append(f"{reaction_text} by {reaction['sender']}")
                clipboard_content.append("")  # Empty line after reactions
            
            clipboard_content.extend([
                "-" * 50,
                contact_name
            ])
        
        # Copy to clipboard
        clipboard_text = "\n".join(clipboard_content)
        pyperclip.copy(clipboard_text)
        print("\nConversation has been copied to clipboard!")
        
        return meaningful_messages
                    
    except sqlite3.OperationalError as e:
        print("Error: Unable to access Messages database.")
        print("You may need to grant Full Disk Access to your terminal application.")
        print(f"\nDetailed error: {str(e)}")
        return []
            
    finally:
        if 'conn' in locals():
            conn.close()

def get_contact_info(phone_number):
    """Get contact information from the AddressBook database"""
    contacts_db_path = os.path.expanduser("~/Library/Application Support/AddressBook/AddressBook-v22.abcddb")
    
    try:
        conn = sqlite3.connect(contacts_db_path)
        cursor = conn.cursor()
        
        # Try multiple possible schemas
        queries = [
            # Modern schema
            """
            SELECT 
                ZFIRSTNAME || ' ' || ZLASTNAME as full_name
            FROM ZABCDRECORD
            JOIN ZABCDPHONENUMBER ON ZABCDRECORD.Z_PK = ZABCDPHONENUMBER.ZOWNER
            WHERE ZFULLNUMBER LIKE ?
            """,
            # Alternative schema
            """
            SELECT 
                ZFIRSTNAME || ' ' || ZLASTNAME as full_name
            FROM ZABCDRECORD
            JOIN ZABCDPHONE ON ZABCDRECORD.Z_PK = ZABCDPHONE.ZOWNER
            WHERE ZPHONE LIKE ?
            """
        ]
        
        # Remove any formatting from phone number for comparison
        clean_number = ''.join(filter(str.isdigit, phone_number))
        if clean_number.startswith('1'):  # Remove leading 1 if present
            clean_number = clean_number[1:]
        search_pattern = f"%{clean_number}%"
        
        for query in queries:
            try:
                cursor.execute(query, (search_pattern,))
                result = cursor.fetchone()
                if result and result[0]:
                    return result[0].strip()
            except sqlite3.OperationalError:
                continue
                
        return None
        
    except sqlite3.OperationalError:
        return None
    finally:
        if 'conn' in locals():
            conn.close()

def main():
    # Get available chats
    chats = get_available_chats()
    
    if not chats:
        print("No chats found or unable to access the database.")
        return
    
    # Display available chats
    print("\nAvailable chats:")
    print("-" * 50)
    for idx, (contact_id, count, name) in enumerate(chats, 1):
        if name:
            print(f"{idx}. {name} ({contact_id}) - {count} messages")
        else:
            print(f"{idx}. {contact_id} - {count} messages")
    
    # Get user selection
    while True:
        try:
            choice = int(input("\nSelect a chat number: "))
            if 1 <= choice <= len(chats):
                break
            print("Invalid selection. Please try again.")
        except ValueError:
            print("Please enter a valid number.")
    
    # Get message limit
    while True:
        limit_input = input("How many recent messages to show? (type 'all' for entire history): ").lower()
        if limit_input == 'all':
            limit = None
            break
        try:
            limit = int(limit_input)
            if limit > 0:
                break
            print("Please enter a positive number.")
        except ValueError:
            print("Please enter a valid number or 'all'.")
    
    # Query messages for selected chat
    selected_contact = chats[choice - 1][0]
    query_messages(selected_contact, limit)

if __name__ == "__main__":
    main()