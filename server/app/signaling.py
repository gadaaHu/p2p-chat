from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from typing import Dict
import json
from . import auth

router = APIRouter()

class ConnectionManager:
    def __init__(self):
        # username -> WebSocket mapping
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, username: str):
        await websocket.accept()
        self.active_connections[username] = websocket

    def disconnect(self, username: str):
        if username in self.active_connections:
            del self.active_connections[username]

    async def send_personal_message(self, message: str, username: str):
        if username in self.active_connections:
            await self.active_connections[username].send_text(message)
            return True
        return False

manager = ConnectionManager()

@router.websocket("/ws/{username}")
async def websocket_endpoint(websocket: WebSocket, username: str):
    # In a real app we would authenticate the websocket using a token parameter
    await manager.connect(websocket, username)
    try:
        while True:
            data = await websocket.receive_text()
            # Relay WebRTC signaling blobs (SDP offers, answers, ICE candidates)
            # Expecting JSON like: {"to": "bob", "type": "offer", "sdp": "..."}
            try:
                parsed = json.loads(data)
                target = parsed.get("to")
                if target:
                    # Append sender info so the recipient knows who it's from
                    parsed["from"] = username
                    await manager.send_personal_message(json.dumps(parsed), target)
            except json.JSONDecodeError:
                pass # Ignore malformed signaling data
                
    except WebSocketDisconnect:
        manager.disconnect(username)
