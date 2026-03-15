import os
import sys
import pickle
from googleapiclient.discovery import build
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.http import MediaFileUpload

# upload_to_drive.py
# Helper script to upload a file to a specific Google Drive folder using OAuth 2.0

# If modifying these scopes, delete the file token.json.
SCOPES = ['https://www.googleapis.com/auth/drive.file']

def get_credentials():
    creds = None
    # The file token.json stores the user's access and refresh tokens, and is
    # created automatically when the authorization flow completes for the first
    # time.
    if os.path.exists('token.json'):
        with open('token.json', 'rb') as token:
            creds = pickle.load(token)
    
    # If there are no (valid) credentials available, let the user log in.
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists('client_secrets.json'):
                print("❌ Error: client_secrets.json not found.")
                print("💡 Download your Desktop OAuth Client ID JSON from Google Cloud Console.")
                sys.exit(1)
            
            flow = InstalledAppFlow.from_client_secrets_file('client_secrets.json', SCOPES)
            creds = flow.run_local_server(port=0)
        
        # Save the credentials for the next run
        with open('token.json', 'wb') as token:
            pickle.dump(creds, token)
    
    return creds

def upload_file(file_path, folder_id):
    creds = get_credentials()
    service = build('drive', 'v3', credentials=creds)

    file_metadata = {
        'name': os.path.basename(file_path),
        'parents': [folder_id]
    }
    
    media = MediaFileUpload(file_path, resumable=True)
    
    print(f"⌛ Uploading {file_metadata['name']} using User OAuth...")
    try:
        file = service.files().create(body=file_metadata, media_body=media, fields='id').execute()
        print(f"✅ Upload Successful! File ID: {file.get('id')}")
    except Exception as e:
        print(f"❌ Upload Failed: {e}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 upload_to_drive.py <file_path> <folder_id>")
        sys.exit(1)
    
    upload_file(sys.argv[1], sys.argv[2])
