from fastapi import APIRouter, Body, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.dependencies import get_current_tourist
from app.models import schemas
from app.services import group_safety


router = APIRouter(prefix="/v3/groups", tags=["Tourist Groups"])


@router.post("")
async def create_group(
    payload: schemas.GroupCreate = Body(default_factory=schemas.GroupCreate),
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    return await group_safety.create_group(
        db,
        tourist_id=tourist_id,
        name=payload.name,
        trip_id=payload.trip_id,
        destination_id=payload.destination_id,
    )


@router.post("/{invite_code}/join")
async def join_group(
    invite_code: str,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    return await group_safety.join_group(db, invite_code=invite_code, tourist_id=tourist_id)


@router.get("/active")
async def get_active_group(
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    group = await group_safety.get_active_group_for_tourist(db, tourist_id)
    if not group:
        return {"active_group": None}
    return {"active_group": await group_safety.get_group_payload(db, group.group_id, current_tourist_id=tourist_id)}


@router.get("/{group_id}/members")
async def get_group_members(
    group_id: str,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    group = await group_safety.assert_group_member(db, group_id, tourist_id)
    return await group_safety.get_group_payload(db, group.group_id, current_tourist_id=tourist_id)


@router.post("/{group_id}/sharing")
async def update_group_sharing(
    group_id: str,
    payload: schemas.GroupSharingUpdate,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    return await group_safety.set_sharing_status(
        db,
        group_ref=group_id,
        tourist_id=tourist_id,
        sharing=payload.sharing,
        sharing_status=payload.sharing_status,
    )


@router.post("/{group_id}/leave")
async def leave_group(
    group_id: str,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    return await group_safety.leave_group(db, group_ref=group_id, tourist_id=tourist_id)
