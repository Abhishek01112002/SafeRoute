from app.db import sqlite_legacy

from tests.conftest import TEST_TOURIST_ID, TEST_TOURIST_TUID


def test_onboard_preview_requires_authority_auth(client, authority_auth_header):
    missing_auth = client.get("/onboard/preview/UK_KED_001")
    assert missing_auth.status_code in {401, 403}

    authorized = client.get(
        "/onboard/preview/UK_KED_001",
        headers=authority_auth_header,
    )
    assert authorized.status_code == 200, authorized.text
    assert authorized.json()["qr_token"].startswith("SAFEROUTE-UK_KED_001-")


def test_media_upload_url_requires_auth(client):
    response = client.post(
        "/v3/media/upload-url",
        json={
            "content_type": "image/jpeg",
            "file_size_bytes": 1024,
            "tuid": TEST_TOURIST_TUID,
        },
    )
    assert response.status_code in {401, 403}


def test_media_upload_url_rejects_foreign_tuid(client, tourist_auth_header):
    response = client.post(
        "/v3/media/upload-url",
        headers=tourist_auth_header,
        json={
            "content_type": "image/jpeg",
            "file_size_bytes": 1024,
            "tuid": "SR-IN-26-FFFFEE123456",
        },
    )
    assert response.status_code == 403


def test_tourist_photo_rejects_cross_tourist_access(client, tourist_auth_header):
    other_tourist_id = "TID-2025-UK-OTHER"
    sqlite_legacy.tourists_db[other_tourist_id] = {
        "tourist_id": other_tourist_id,
        "tuid": "SR-IN-26-OTHER1234567",
        "full_name": "Other Tourist",
        "photo_object_key": f"uploaded_files/tourist_{other_tourist_id}/profile.jpg",
    }

    response = client.get(
        f"/v3/tourist/photo/{other_tourist_id}",
        headers=tourist_auth_header,
    )

    assert response.status_code == 403


def test_media_download_blocks_path_traversal(client, tourist_auth_header):
    response = client.get(
        f"/v3/media/download/uploaded_files/tourist_{TEST_TOURIST_ID}/../tourist_other/profile.jpg",
        headers=tourist_auth_header,
    )
    assert response.status_code == 403
