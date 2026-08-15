import pytest
from unittest.mock import patch
from app import app, mongo
from bson.objectid import ObjectId


@pytest.fixture
def client():
    app.config["TESTING"] = True
    client = app.test_client()
    with app.app_context():
        mongo.db.students.delete_many({})
        mongo.db.students.insert_one({
            "_id": ObjectId("66fddff25f4b5f6a0a123456"),
            "name": "Test Student",
            "email": "test@student.com",
            "course": "Flask",
        })
    yield client
    with app.app_context():
        mongo.cx.drop_database("test_student_db")


def test_home_page(client):
    response = client.get('/')
    assert response.status_code == 200
    assert b"Test Student" in response.data


def test_add_student(client):
    response = client.post('/add', data={"name": "New User", "email": "new@user.com", "course": "Python"}, follow_redirects=True)
    assert response.status_code == 200
    assert b"New User" in response.data


def test_update_student(client):
    response = client.post('/update/66fddff25f4b5f6a0a123456', data={"name": "Updated Name", "email": "updated@student.com", "course": "Updated Course"}, follow_redirects=True)
    assert response.status_code == 200
    assert b"Updated Name" in response.data


def test_delete_student(client):
    with app.app_context():
        student_id = mongo.db.students.insert_one({"name": "Temp User", "email": "temp@user.com", "course": "Temp Course"}).inserted_id
    response = client.get(f'/delete/{student_id}', follow_redirects=True)
    assert response.status_code == 200
    assert b"Temp User" not in response.data


def test_health_success(client):
    with patch.object(mongo, "cx") as mock_client:
        mock_client.admin.command.return_value = {"ok": 1}
        response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json() == {"status": "healthy", "mongodb": "connected"}


def test_health_failure(client):
    with patch.object(mongo, "cx") as mock_client:
        mock_client.admin.command.side_effect = RuntimeError("unavailable")
        response = client.get('/health')
    assert response.status_code == 503
    assert response.get_json() == {"status": "unhealthy", "mongodb": "disconnected"}

