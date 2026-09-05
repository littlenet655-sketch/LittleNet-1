import os
import modal

print("Syncing uploads/ directory to modal.Volume('littlenet-uploads')...")
vol = modal.Volume.from_name("littlenet-uploads")

with vol.batch_upload(force=True) as batch:
    for root, dirs, files in os.walk('uploads'):
        for f in files:
            local_path = os.path.join(root, f)
            rel_path = os.path.relpath(local_path, 'uploads').replace('\\', '/')
            remote_path = '/' + rel_path
            print(f"Uploading {local_path} -> {remote_path}")
            batch.put_file(local_path, remote_path)

print("Volume sync finished! Verifying volume listing...")
entries = vol.listdir('/')
for entry in entries:
    print(f"  {entry.path} ({entry.type})")
print("Done!")
