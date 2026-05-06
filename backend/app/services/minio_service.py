# app/services/minio_service.py
"""
MinIO / S3-compatible object storage service.
Generates presigned PUT URLs for mobile uploads and presigned GET URLs
for authority scan responses (5-minute expiry, no permanent URLs returned).
Degrades gracefully if MinIO is unavailable.
"""
from typing import Optional
from app.config import settings
from app.logging_config import logger


class MinIOService:
    def __init__(self):
        self._client = None
        self._bucket = settings.MINIO_BUCKET
        self._initialized = False

    def _ensure_initialized(self) -> None:
        if self._initialized:
            return
        self._initialized = True
        try:
            import boto3
            from botocore.config import Config

            self._client = boto3.client(
                "s3",
                endpoint_url=f"{'https' if settings.MINIO_USE_SSL else 'http'}://{settings.MINIO_ENDPOINT}",
                aws_access_key_id=settings.MINIO_ACCESS_KEY,
                aws_secret_access_key=settings.MINIO_SECRET_KEY,
                config=Config(
                    signature_version="s3v4",
                    connect_timeout=2,
                    read_timeout=2,
                    retries={'max_attempts': 0}
                ),
                region_name="us-east-1",
            )
            self._ensure_bucket()
            logger.info(f"✅ MinIOService: Connected to {settings.MINIO_ENDPOINT}, bucket={self._bucket}")
        except Exception as e:
            logger.error(f"🔴 MinIOService: Init failed — photo uploads disabled. {e}")
            self._client = None

    def _ensure_bucket(self) -> None:
        if self._client is None:
            return
        try:
            existing = [b["Name"] for b in self._client.list_buckets().get("Buckets", [])]
            if self._bucket not in existing:
                self._client.create_bucket(Bucket=self._bucket)
                logger.info(f"✅ MinIOService: Created bucket '{self._bucket}'.")
        except Exception as e:
            logger.warning(f"⚠️  MinIOService: Could not verify bucket: {e}")

    @property
    def is_available(self) -> bool:
        self._ensure_initialized()
        return self._client is not None

    def get_presigned_upload_url(
        self,
        object_key: str,
        content_type: str = "image/jpeg",
        expiry_seconds: int = 300,
    ) -> str:
        self._ensure_initialized()
        if not self._client:
            raise RuntimeError("MinIOService: Storage unavailable.")
        return self._client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self._bucket,
                "Key": object_key,
                "ContentType": content_type,
            },
            ExpiresIn=expiry_seconds,
            HttpMethod="PUT",
        )

    def get_presigned_download_url(
        self,
        object_key: str,
        expiry_seconds: int = 300,
    ) -> Optional[str]:
        self._ensure_initialized()
        if not self._client or not object_key:
            return None
        try:
            return self._client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self._bucket, "Key": object_key},
                ExpiresIn=expiry_seconds,
            )
        except Exception as e:
            logger.error(f"🔴 MinIOService: presigned download failed for {object_key}: {e}")
            return None

    def delete_object(self, object_key: str) -> None:
        self._ensure_initialized()
        if not self._client or not object_key:
            return
        try:
            self._client.delete_object(Bucket=self._bucket, Key=object_key)
            logger.info(f"MinIOService: Deleted {object_key}")
        except Exception as e:
            logger.error(f"🔴 MinIOService: delete failed for {object_key}: {e}")


# Module-level singleton
minio_service = MinIOService()
