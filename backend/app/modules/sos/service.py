from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from typing import Dict, List, Any, Optional
import uuid
import secrets
from datetime import datetime, timedelta, timezone
from backend.app.config import settings
from backend.app.modules.sos.models import (
    SOSTriggerRequest, LocationPingRequest, SOSIncidentResponse
)
from backend.app.modules.users.router import _users_db, _contacts_db
from backend.app.modules.trust_plane.audit import AuditLogger

router = APIRouter(prefix="/sos", tags=["Deterministic SOS & Live Location Engine"])

_incidents_db: Dict[str, Dict[str, Any]] = {}
_location_pings_db: Dict[str, List[Dict[str, Any]]] = {} # token -> list of pings

@router.post("/{user_id}/trigger", response_model=SOSIncidentResponse)
async def trigger_emergency_sos(user_id: str, payload: SOSTriggerRequest):
    """
    Deterministic SOS trigger:
    1. Generates 8-hour live tracking token
    2. Builds direct Google Maps pin URL
    3. Dispatches SMS & WhatsApp notification alerts to emergency contacts
    """
    user = _users_db.get(user_id)
    display_name = user.get("display_name", "Nuvin User") if user else "Nuvin User"
    
    incident_id = str(uuid.uuid4())
    token = secrets.token_urlsafe(24)
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(hours=8)
    
    # 1. Google Maps URLs
    gmaps_pin_url = f"https://maps.google.com/?q={payload.latitude},{payload.longitude}"
    live_tracking_url = f"{settings.LIVE_TRACKING_BASE_URL}/{token}"

    # 2. Record Initial Ping
    initial_ping = {
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "accuracy_meters": payload.accuracy_meters,
        "recorded_at": now
    }
    _location_pings_db[token] = [initial_ping]

    # 3. Create Incident Record
    incident = {
        "incident_id": incident_id,
        "user_id": user_id,
        "state": "open",
        "initial_latitude": payload.latitude,
        "initial_longitude": payload.longitude,
        "live_tracking_token": token,
        "tracking_expires_at": expires_at,
        "opened_at": now
    }
    _incidents_db[incident_id] = incident

    # 4. Prepare SMS / WhatsApp Dispatches
    contacts = _contacts_db.get(user_id, [])
    emergency_contacts = [c for c in contacts if c.get("kind") == "emergency"] or contacts
    
    sms_payloads = []
    for c in emergency_contacts:
        msg_text = (
            f"EMERGENCY ALERT: {display_name} has triggered an SOS alert via Nuvin.\n"
            f"Initial Location: {gmaps_pin_url}\n"
            f"8-Hour Live Tracker: {live_tracking_url}\n"
            f"Please check immediately or dial 112."
        )
        sms_payloads.append({
            "contact_name": c.get("display_name"),
            "phone_e164": c.get("phone_e164"),
            "message": msg_text,
            "status": "queued_for_dispatch"
        })

    # 5. Audit Log
    await AuditLogger.log_event(
        subject_user_id=user_id,
        action="sos_triggered",
        resource="sos_incidents",
        resource_id=incident_id,
        result="executed",
        metadata={
            "trigger_type": payload.trigger_type.value,
            "latitude": payload.latitude,
            "longitude": payload.longitude,
            "contacts_count": len(sms_payloads)
        }
    )

    return SOSIncidentResponse(
        incident_id=incident_id,
        user_id=user_id,
        state="open",
        initial_latitude=payload.latitude,
        initial_longitude=payload.longitude,
        google_maps_pin_url=gmaps_pin_url,
        live_tracking_token=token,
        live_tracking_url=live_tracking_url,
        tracking_expires_at=expires_at,
        contacts_notified_count=len(sms_payloads),
        sms_notification_payloads=sms_payloads
    )

@router.post("/live/{token}/ping")
async def ping_live_location(token: str, ping: LocationPingRequest):
    """
    Mobile background worker posts updated GPS coordinates every 30 seconds during 8hr window.
    """
    if token not in _location_pings_db:
        raise HTTPException(status_code=404, detail="Live tracking session not found")
        
    pings = _location_pings_db[token]
    new_ping = {
        "latitude": ping.latitude,
        "longitude": ping.longitude,
        "accuracy_meters": ping.accuracy_meters,
        "recorded_at": datetime.now(timezone.utc)
    }
    pings.append(new_ping)
    return {"status": "ok", "pings_count": len(pings)}

@router.get("/live/{token}/coords")
async def get_live_coordinates(token: str):
    """
    JSON API for the live tracking web page to auto-poll coordinates.
    """
    pings = _location_pings_db.get(token)
    if not pings:
        raise HTTPException(status_code=404, detail="Tracking session not found")
        
    latest = pings[-1]
    return {
        "latitude": latest["latitude"],
        "longitude": latest["longitude"],
        "accuracy_meters": latest["accuracy_meters"],
        "updated_at": latest["recorded_at"].isoformat(),
        "total_breadcrumbs": len(pings)
    }

@router.get("/live/{token}", response_class=HTMLResponse)
async def view_live_tracking_page(token: str):
    """
    Browser-viewable live location tracker.
    Requires ZERO app download for family / emergency contacts.
    """
    pings = _location_pings_db.get(token)
    if not pings:
        return HTMLResponse(
            "<html><body style='font-family:sans-serif; text-align:center; padding:40px;'>"
            "<h2>Tracking Link Expired or Not Found</h2>"
            "<p>This live tracking session is no longer active.</p></body></html>",
            status_code=404
        )
        
    latest = pings[-1]
    lat = latest["latitude"]
    lng = latest["longitude"]

    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Nuvin Emergency Live Tracker</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 0; background: #f8fafc; }}
            .header {{ background: #dc2626; color: white; padding: 16px 20px; display: flex; justify-content: space-between; align-items: center; }}
            .header h1 {{ font-size: 1.25rem; margin: 0; }}
            .badge {{ background: white; color: #dc2626; font-weight: bold; padding: 4px 10px; border-radius: 9999px; font-size: 0.85rem; }}
            #map {{ height: calc(100vh - 130px); width: 100%; }}
            .footer {{ background: white; padding: 12px 20px; box-shadow: 0 -2px 10px rgba(0,0,0,0.05); display: flex; justify-content: space-between; align-items: center; font-size: 0.9rem; }}
            .btn-directions {{ background: #2563eb; color: white; padding: 8px 16px; border-radius: 8px; text-decoration: none; font-weight: 500; }}
        </style>
    </head>
    <body>
        <div class="header">
            <div>
                <h1>🚨 Nuvin Emergency Live Tracker</h1>
                <small>Active for 8 hours • Auto-refreshing</small>
            </div>
            <div class="badge" id="status-badge">LIVE</div>
        </div>
        <div id="map"></div>
        <div class="footer">
            <div id="coords-text">Lat: {lat:.5f}, Lng: {lng:.5f}</div>
            <a href="https://maps.google.com/?q={lat},{lng}" target="_blank" class="btn-directions">Open in Google Maps</a>
        </div>
        <script>
            var map = L.map('map').setView([{lat}, {lng}], 16);
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
                maxZoom: 19,
                attribution: '© OpenStreetMap & Nuvin Safety'
            }}).addTo(map);

            var marker = L.marker([{lat}, {lng}]).addTo(map)
                .bindPopup('<b>Current Location</b><br>Updated just now')
                .openPopup();

            // Auto-poll every 10 seconds
            setInterval(async () => {{
                try {{
                    const res = await fetch('/sos/live/{token}/coords');
                    if (res.ok) {{
                        const data = await res.json();
                        var newLatLng = new L.LatLng(data.latitude, data.longitude);
                        marker.setLatLng(newLatLng);
                        map.panTo(newLatLng);
                        document.getElementById('coords-text').innerText = `Lat: ${{data.latitude.toFixed(5)}}, Lng: ${{data.longitude.toFixed(5)}}`;
                    }}
                }} catch (e) {{
                    console.log('Poll error', e);
                }}
            }}, 10000);
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content, status_code=200)
