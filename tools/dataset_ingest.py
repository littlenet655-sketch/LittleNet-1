import os
import csv
import json
import uuid
import shutil
import hashlib
import zipfile
import logging
from typing import Dict, Any, List, Optional

logger = logging.getLogger("littlenet.dataset_ingest")

class DatasetIngestionPipeline:
    """
    Standardized ingestion engine for child-safe educational content datasets.
    Validates ZIPs, de-duplicates using SHA-256, standardizes naming (IMG_000001 / REEL_000001),
    applies full multi-tier moderation, and generates audit reports.
    """
    def __init__(self, output_base: str = "uploads/dataset_ingested"):
        self.output_base = output_base
        os.makedirs(self.output_base, exist_ok=True)
        self.seen_hashes = set()

    def compute_sha256(self, filepath: str) -> str:
        h = hashlib.sha256()
        with open(filepath, 'rb') as f:
            while chunk := f.read(65536):
                h.update(chunk)
        return h.hexdigest()

    def process_archive(self, zip_path: str, author_user_id: int = 1) -> Dict[str, Any]:
        report = {
            "archive": os.path.basename(zip_path),
            "total_items": 0,
            "ingested_count": 0,
            "duplicates_count": 0,
            "blocked_count": 0,
            "review_count": 0,
            "duplicates": [],
            "missing_metadata": [],
            "processed_items": []
        }

        extract_dir = os.path.join(self.output_base, f"temp_{uuid.uuid4().hex[:8]}")
        os.makedirs(extract_dir, exist_ok=True)

        try:
            with zipfile.ZipFile(zip_path, 'r') as zf:
                zf.extractall(extract_dir)

            # Look for metadata.csv
            csv_path = None
            for root, _, files in os.walk(extract_dir):
                for f in files:
                    if f.lower() == "metadata.csv":
                        csv_path = os.path.join(root, f)
                        break

            metadata_map = {}
            if csv_path and os.path.isfile(csv_path):
                with open(csv_path, 'r', encoding='utf-8', errors='replace') as cf:
                    reader = csv.DictReader(cf)
                    for row in reader:
                        fn = row.get("original_filename") or row.get("filename")
                        if fn:
                            metadata_map[fn.strip()] = row

            # Walk and process media files
            image_idx = 1
            reel_idx = 1

            for root, _, files in os.walk(extract_dir):
                for f in files:
                    if f.lower() in ("metadata.csv", "metadata.json", "report.md"):
                        continue
                    ext = f.rsplit('.', 1)[-1].lower() if '.' in f else ''
                    if ext not in ('jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm'):
                        continue

                    report["total_items"] += 1
                    raw_path = os.path.join(root, f)
                    file_hash = self.compute_sha256(raw_path)

                    if file_hash in self.seen_hashes:
                        report["duplicates_count"] += 1
                        report["duplicates"].append({"filename": f, "sha256": file_hash})
                        continue

                    self.seen_hashes.add(file_hash)
                    meta = metadata_map.get(f, {})
                    if not meta:
                        report["missing_metadata"].append(f)

                    # Determine type & generate standardized ID
                    is_video = ext in ('mp4', 'mov', 'webm')
                    if is_video:
                        std_id = f"REEL_{reel_idx:06d}"
                        reel_idx += 1
                        dest_sub = "reels"
                    else:
                        std_id = f"IMG_{image_idx:06d}"
                        image_idx += 1
                        dest_sub = "images"

                    dest_dir = os.path.join(self.output_base, dest_sub)
                    os.makedirs(dest_dir, exist_ok=True)
                    dest_file = f"{std_id}.{ext}"
                    dest_path = os.path.join(dest_dir, dest_file)
                    shutil.copy2(raw_path, dest_path)

                    caption = meta.get("caption") or f"Safe learning exploration {std_id}"
                    category = meta.get("category") or "Education"
                    audience = meta.get("audience_age_group") or "ALL"

                    # 1. Text & PII screening
                    from safety.pii_service import scan_pii
                    pii_res = scan_pii(caption)
                    if pii_res["detected"]:
                        report["blocked_count"] += 1
                        continue

                    # 2. Visual / video screening
                    from safety.moderation_service import evaluate
                    from safety.policy import decide
                    from config import Config

                    sig, d = evaluate(author_user_id, "VIDEO" if is_video else "IMAGE", dest_path)
                    if d.action == "BLOCK":
                        report["blocked_count"] += 1
                        try: os.unlink(dest_path)
                        except OSError: pass
                        continue

                    # 3. Insert into database
                    from database.connection import execute
                    status = "ALLOWED" if d.action == "ALLOW" else "REVIEW"
                    if status == "REVIEW":
                        report["review_count"] += 1
                    else:
                        report["ingested_count"] += 1

                    row = execute(
                        '''INSERT INTO posts(child_id, media_type, media_path, caption, content_category,
                                             audience_age_group, is_story, is_reel, safety_score,
                                             is_safe, moderation_status, moderation_reason)
                           VALUES(%s, %s, %s, %s, %s, %s, FALSE, %s, %s, %s, %s, %s)
                           RETURNING post_id''',
                        (author_user_id, "VIDEO" if is_video else "IMAGE", dest_path, caption,
                         category, audience, is_video, d.risk, status == "ALLOWED", status, d.reason),
                        returning=True
                    )

                    report["processed_items"].append({
                        "post_id": row.get("post_id"),
                        "standard_id": std_id,
                        "original_filename": f,
                        "sha256": file_hash,
                        "status": status,
                        "category": category
                    })

        finally:
            shutil.rmtree(extract_dir, ignore_errors=True)

        # Write reports
        self._write_reports(report)
        return report

    def _write_reports(self, report: Dict[str, Any]):
        out_dir = self.output_base
        # 1. duplicates.csv
        with open(os.path.join(out_dir, "duplicates.csv"), "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["filename", "sha256"])
            writer.writeheader()
            writer.writerows(report.get("duplicates", []))

        # 2. metadata.json
        with open(os.path.join(out_dir, "metadata.json"), "w", encoding="utf-8") as f:
            json.dump(report.get("processed_items", []), f, indent=2)

        # 3. processing_report.md
        md = (
            f"# Dataset Ingestion Processing Report: {report['archive']}\n\n"
            f"- **Total Files Evaluated**: {report['total_items']}\n"
            f"- **Successfully Ingested**: {report['ingested_count']}\n"
            f"- **Duplicates Excluded**: {report['duplicates_count']}\n"
            f"- **Safety Blocks**: {report['blocked_count']}\n"
            f"- **Queued for Review**: {report['review_count']}\n"
            f"- **Missing Metadata Files**: {len(report['missing_metadata'])}\n"
        )
        with open(os.path.join(out_dir, "processing_report.md"), "w", encoding="utf-8") as f:
            f.write(md)

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        pipeline = DatasetIngestionPipeline()
        res = pipeline.process_archive(sys.argv[1])
        print(f"Processed: {res['ingested_count']} ingested, {res['duplicates_count']} duplicates.")
    else:
        print("Usage: python tools/dataset_ingest.py <path_to_collection.zip>")
