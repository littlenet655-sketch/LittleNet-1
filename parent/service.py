from database.connection import fetch_one, fetch_all, execute

def children(parent_id):
    return fetch_all('''
        SELECT DISTINCT u.user_id, u.full_name, cp.profile_picture 
        FROM parent_child_map m 
        JOIN users u ON u.user_id = m.child_id 
        LEFT JOIN child_profiles cp ON cp.child_id = u.user_id 
        JOIN users p ON p.user_id = %s
        WHERE m.parent_id = %s 
           OR m.verified_parent_id = %s 
           OR LOWER(m.parent_email) = LOWER(p.email)
    ''', (parent_id, parent_id, parent_id))

def owns(parent_id, child_id):
    return bool(fetch_one('''
        SELECT 1 
        FROM parent_child_map m
        JOIN users p ON p.user_id = %s
        WHERE m.child_id = %s 
          AND (m.parent_id = %s OR m.verified_parent_id = %s OR LOWER(m.parent_email) = LOWER(p.email))
    ''', (parent_id, child_id, parent_id, parent_id)))

def pending_follows(parent_id):
    return fetch_all('''
        SELECT f.child_id, u1.full_name requester_name, f.following_child_id, u2.full_name target_name 
        FROM followers f 
        JOIN users u1 ON u1.user_id = f.child_id 
        JOIN users u2 ON u2.user_id = f.following_child_id 
        WHERE f.approved = FALSE 
          AND f.child_id IN (
              SELECT m.child_id 
              FROM parent_child_map m
              JOIN users p ON p.user_id = %s
              WHERE m.parent_id = %s OR m.verified_parent_id = %s OR LOWER(m.parent_email) = LOWER(p.email)
          ) 
        ORDER BY f.created_at
    ''', (parent_id, parent_id, parent_id))
