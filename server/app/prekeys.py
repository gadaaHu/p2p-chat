from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from . import database, models, schemas, auth

router = APIRouter()

@router.post("/keys", response_model=dict)
def upload_prekeys(
    bundle: schemas.PreKeyBundleUpload, 
    db: Session = Depends(database.get_db), 
    current_user: models.User = Depends(auth.get_current_user)
):
    # Verify the user matches the bundle
    if current_user.identity_key != bundle.identity_key:
        raise HTTPException(status_code=400, detail="Identity key mismatch")
    
    current_user.registration_id = bundle.registration_id
    
    # Store Signed PreKey
    db_signed = db.query(models.SignedPreKey).filter_by(user_id=current_user.id).first()
    if db_signed:
        db.delete(db_signed)
        
    new_signed = models.SignedPreKey(
        user_id=current_user.id,
        key_id=bundle.signed_prekey.key_id,
        public_key=bundle.signed_prekey.public_key,
        signature=bundle.signed_prekey.signature
    )
    db.add(new_signed)
    
    # Store One-Time PreKeys
    # Clear old keys if necessary or just append
    for pk in bundle.prekeys:
        new_pk = models.PreKey(
            user_id=current_user.id,
            key_id=pk.key_id,
            public_key=pk.public_key
        )
        db.add(new_pk)
        
    db.commit()
    return {"status": "success", "message": f"Uploaded {len(bundle.prekeys)} prekeys"}

@router.get("/keys/{username}", response_model=schemas.PreKeyBundleResponse)
def get_prekey_bundle(
    username: str, 
    db: Session = Depends(database.get_db), 
    current_user: models.User = Depends(auth.get_current_user)
):
    target_user = db.query(models.User).filter(models.User.username == username).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")
        
    signed_pk = db.query(models.SignedPreKey).filter_by(user_id=target_user.id).first()
    if not signed_pk:
        raise HTTPException(status_code=404, detail="User has not uploaded keys")
        
    # Get a single one-time prekey and remove it
    otp = db.query(models.PreKey).filter_by(user_id=target_user.id).first()
    if otp:
        db.delete(otp)
        db.commit()
    
    response_otp = None
    if otp:
        response_otp = schemas.PreKeyCreate(key_id=otp.key_id, public_key=otp.public_key)
        
    return schemas.PreKeyBundleResponse(
        identity_key=target_user.identity_key,
        registration_id=target_user.registration_id,
        signed_prekey=schemas.SignedPreKeyCreate(
            key_id=signed_pk.key_id,
            public_key=signed_pk.public_key,
            signature=signed_pk.signature
        ),
        prekey=response_otp
    )
