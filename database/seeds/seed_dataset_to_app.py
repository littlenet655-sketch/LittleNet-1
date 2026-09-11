"""
LittleNet Dataset Ingestion & Seeding Script
Populates the LittleNet database with media, captions, and hashtags from D:\aitprojects\database.
"""

import os
import csv
import zipfile
import shutil
from pathlib import Path
from db import query_one, execute

CSV_PATH = os.path.join(os.path.dirname(__file__), "dataset_posts.csv")
DATABASE_DIR = r"D:\aitprojects\database"
TARGET_STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "static", "uploads", "posts")

def seed_dataset(include_blocked=False):
    os.makedirs(TARGET_STATIC_DIR, exist_ok=True)

    if not os.path.exists(CSV_PATH):
        print(f"Error: CSV file not found at {CSV_PATH}")
        return

    # Check or create a demo child user for seeded content
    demo_child = query_one("SELECT user_id FROM users WHERE role = 'child' LIMIT 1")
    if not demo_child:
        print("Creating a verified demo child user for dataset content...")
        parent = query_one("SELECT user_id FROM users WHERE role = 'parent' LIMIT 1")
        if not parent:
            execute("INSERT INTO users(role, name, email, is_verified) VALUES('parent', 'Demo Parent', 'parent@littlenet.local', TRUE)")
            parent = query_one("SELECT user_id FROM users WHERE role = 'parent' LIMIT 1")

        execute("""
            INSERT INTO users(role, parent_id, name, age, username, is_verified)
            VALUES('child', %s, 'LittleNet Explorer', 10, 'littlenet_explorer', TRUE)
        """, (parent['user_id'],))
        demo_child = query_one("SELECT user_id FROM users WHERE username = 'littlenet_explorer'")

    child_id = demo_child['user_id']
    print(f"Using child author account (ID: {child_id}) for seeding posts.")

    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    inserted_count = 0
    skipped_count = 0

    for row in rows:
        is_safe = row['is_safe'].lower() == 'true'
        if not is_safe and not include_blocked:
            skipped_count += 1
            continue

        archive_file = row['archive_file']
        fn = row['filename']
        raw_cat = row['raw_category']

        # Extract file to static/uploads/posts/
        zip_path = os.path.join(DATABASE_DIR, archive_file)
        if not os.path.exists(zip_path):
            zip_path = os.path.join(r"D:\aitprojects", archive_file)
        dest_filename = f"{raw_cat}_{fn}".replace(" ", "_")
        dest_file_path = os.path.join(TARGET_STATIC_DIR, dest_filename)
        rel_media_path = f"static/uploads/posts/{dest_filename}"

        if not os.path.exists(dest_file_path) and os.path.exists(zip_path):
            try:
                with zipfile.ZipFile(zip_path, 'r') as zf:
                    # find matching entry
                    for info in zf.infolist():
                        if os.path.basename(info.filename) == fn:
                            with zf.open(info) as src, open(dest_file_path, 'wb') as dst:
                                shutil.copyfileobj(src, dst)
                            break
            except Exception as e:
                print(f"Error extracting {fn}: {e}")

        # Format complete caption including hashtags
        full_caption = f"{row['title']}\n\n{row['caption']}\n\n{row['hashtags']}"

        # Insert post into database
        try:
            execute("""
                INSERT INTO posts(
                    child_id, media_type, media_path, caption,
                    content_category, audience_age_group, is_story, is_reel,
                    safety_score, adult_score, is_safe, moderation_status, moderation_reason
                ) VALUES (
                    %s, %s, %s, %s,
                    %s, %s, %s, %s,
                    %s, %s, %s, %s, %s
                )
            """, (
                child_id,
                row['media_type'],
                rel_media_path,
                full_caption,
                row['app_category'] if row['app_category'] in ['Nature', 'Art', 'Education', 'Science', 'Other'] else 'Nature',
                row['audience_age_group'] if row['audience_age_group'] in ['ALL', '6-8', '9-11', '12-13', '14-18'] else 'ALL',
                False,
                row['is_reel'].lower() == 'true',
                float(row['safety_score']),
                float(row['adult_score']),
                is_safe,
                row['moderation_status'],
                row['safety_reason']
            ))
            inserted_count += 1
        except Exception as e:
            print(f"Error inserting {fn}: {e}")

    print(f"\nSeeding complete!")
    print(f"  Successfully inserted: {inserted_count} posts")
    print(f"  Skipped (quarantined): {skipped_count} posts")

if __name__ == "__main__":
    import sys
    inc_blocked = "--include-blocked" in sys.argv
    seed_dataset(include_blocked=inc_blocked)
