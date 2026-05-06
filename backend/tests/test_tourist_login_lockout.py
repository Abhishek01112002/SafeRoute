from app.routes import tourist as tourist_routes


def test_tourist_login_locks_after_15_failed_attempts(client):
    tourist_id = "TID-2099-UK-BAD01"
    tourist_routes._login_attempts.pop(tourist_id, None)

    for attempt in range(1, tourist_routes.MAX_LOGIN_ATTEMPTS + 1):
        response = client.post(
            "/v3/tourist/login",
            json={"tourist_id": tourist_id},
        )
        assert response.status_code == 404
        assert response.json()["detail"]["remaining_attempts"] == (
            tourist_routes.MAX_LOGIN_ATTEMPTS - attempt
        )

    locked_response = client.post(
        "/v3/tourist/login",
        json={"tourist_id": tourist_id},
    )

    assert tourist_routes.MAX_LOGIN_ATTEMPTS == 15
    assert locked_response.status_code == 429
    assert locked_response.json()["detail"]["retry_after_seconds"] > 0

    tourist_routes._login_attempts.pop(tourist_id, None)
