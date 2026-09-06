# Step 6 — Two-parent friendship contract

Target flow:

1. Child A searches/finds Child B and sends a friend request.
2. The request is not active and messaging/content interaction remains blocked.
3. Parent A must approve the outgoing request.
4. Only then does Parent B receive the incoming approval request.
5. Parent B must approve before the friendship becomes ACTIVE.
6. `followers.approved` becomes true only when both parent approvals are complete.
7. Rejecting before activation removes the pending request.
8. Existing approved relationships are migrated as both-parent-approved for compatibility.

No child can self-approve a friendship.