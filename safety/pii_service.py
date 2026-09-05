import re
from typing import Dict, Any, List, Tuple

# Word-to-digit translation map for spelled-out phone numbers
WORD_DIGITS = {
    'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
    'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9'
}

# Regex for standard and formatted phone numbers (Indian and global)
# Matches: 9876543210, +91 98765 43210, +91-9876543210, 987-654-3210, (987) 654-3210, 9 8 7 6 5 4 3 2 1 0
RE_PHONE_STANDARD = re.compile(
    r'(?:\+?91[\s\-]?)?(?:\(?\b[6-9]\d{2}\)?[\s\-]?\d{3}[\s\-]?\d{4}\b)|'
    r'(?:\b(?:\d[\s\-_.]?){9,11}\d\b)'
)

# Email address regex (standard and obfuscated "user at domain dot com")
RE_EMAIL_STANDARD = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')
RE_EMAIL_OBFUSCATED = re.compile(r'\b[A-Za-z0-9._%+-]+\s+(?:at|@)\s+[A-Za-z0-9.-]+\s+(?:dot|\.)\s+[A-Za-z]{2,}\b', re.IGNORECASE)

# URLs, IPs, and obfuscated domains ("example dot com", "hxxps://example[.]com")
RE_URL_STANDARD = re.compile(r'(?:https?://|www\.)[^\s/$.?#].[^\s]*', re.IGNORECASE)
RE_URL_DOMAIN = re.compile(r'\b[a-zA-Z0-9-]{2,}\.(?:com|org|net|in|io|co|xyz|me|app|link|top|site|club|live)\b', re.IGNORECASE)
RE_URL_OBFUSCATED = re.compile(
    r'(?:h[tx]{2}ps?://[^\s]+)|'
    r'\b[a-zA-Z0-9-]{2,}\s*(?:\[\.\]|\(\.\)|\s+dot\s+|\.\s*)(?:com|org|net|in|io|co|xyz|app|link)\b',
    re.IGNORECASE
)
RE_IP_ADDRESS = re.compile(r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b')

# Social media handle and off-platform solicitation triggers
RE_SOCIAL_HANDLES = re.compile(
    r'(?:\b(?:insta(?:gram)?|snap(?:chat)?|tele(?:gram)?|discord|whatsapp|wa|roblox)\s*(?:id|handle|username|name)?\s*(?:is|:|@|\s)?\s*([A-Za-z0-9._]{3,30}))|'
    r'(?:@([A-Za-z0-9._]{3,30}))|'
    r'(?:\b(?:what\'?s\s*app|whatsapp)\s+me\b)|'
    r'(?:\b(?:add|dm|text|call|ping|follow|msg|message)\s+me\s+(?:on\s+)?(?:insta|snap|telegram|discord|whatsapp|roblox|phone))\b',
    re.IGNORECASE
)

# Address / Physical location sharing cues
RE_ADDRESS_SHARING = re.compile(
    r'\b(?:my\s+(?:house|home|street|flat|apartment|school)?\s*address\s+is|'
    r'i\s+live\s+(?:at|in|near)\b[^\n,.]+(?:street|road|layout|nagar|colony|apartments|cross|main|lane|block|sector)|'
    r'meet\s+me\s+(?:at|outside|near|after\s+school\b)|'
    r'give\s+me\s+your\s+address|'
    r'where\s+(?:is\s+your\s+school|do\s+you\s+(?:live|go\s+to\s+school)))\b',
    re.IGNORECASE
)

# Phrases nudging contact sharing / photo requests
RE_CONTACT_NUDGE = re.compile(
    r'\b(?:'
    r'(?:give|send|share|tell)\s+me\s+your\s+(?:number|phone|insta|snap|email|whatsapp|address|location)|'
    r'send\s+(?:me\s+a\s+|your\s+)(?:selfie|picture|photo|number)|'
    r'(?:call|text)\s+me(?:\s+at)?|'
    r'share\s+your\s+(?:number|location)'
    r')\b',
    re.IGNORECASE
)

# Secrecy cues (high-risk grooming indicators)
RE_SECRECY_CUES = re.compile(
    r'\b(?:don\'?t\s+tell\s+(?:your\s+)?(?:parents|anyone|mom|dad)|'
    r'(?:let\'?s\s+)?keep\s+(?:this|it)\s+(?:a\s+)?secret)\b',
    re.IGNORECASE
)

def _check_spelled_out_numbers(text: str) -> Tuple[bool, str]:
    """Detects word-spelled numbers or mixed numeric/word numbers like '984 five zero one two three four five'."""
    low = text.lower()
    for w, d in WORD_DIGITS.items():
        low = re.sub(r'\b' + w + r'\b', d, low)
    digits = re.sub(r'\D', '', low)
    if len(digits) == 10 and digits[0] in '6789':
        return True, digits
    if len(digits) == 12 and digits.startswith('91') and digits[2] in '6789':
        return True, digits
    return False, ""

def scan_pii(text: str) -> Dict[str, Any]:
    """
    Deterministic server-side screening for PII, external contacts, and off-platform solicitation.
    Never sends data externally. Returns structured safety decisions.
    """
    if not text or not isinstance(text, str):
        return {
            "detected": False,
            "categories": [],
            "severity": "LOW",
            "policy_action": "ALLOW",
            "redacted_text": "",
            "reason_codes": []
        }

    raw = text.strip()
    categories = []
    reason_codes = []
    redacted = raw

    # 1. Phone number check (digits and formatted)
    # Check digits-only sequence in string to catch spaced numbers: "9 8 4 5 0 1 2 3 4 5"
    digits_only = re.sub(r'\D', '', raw)
    # If string contains a 10-12 digit sequence matching Indian mobile or standard phone
    has_raw_phone = False
    if len(digits_only) == 10 and digits_only[0] in '6789':
        has_raw_phone = True
    elif len(digits_only) == 12 and digits_only.startswith('91') and digits_only[2] in '6789':
        has_raw_phone = True

    phone_matches = RE_PHONE_STANDARD.findall(raw)
    valid_phones = [p for p in phone_matches if len(re.sub(r'\D', '', p)) in (10, 11, 12)]

    spelled_phone, _ = _check_spelled_out_numbers(raw)

    if valid_phones or has_raw_phone or spelled_phone or RE_CONTACT_NUDGE.search(raw):
        categories.append("PHONE_NUMBER")
        reason_codes.append("DETECTED_PHONE_OR_CONTACT_REQUEST")
        redacted = RE_PHONE_STANDARD.sub("[PHONE]", redacted)
        if spelled_phone:
            redacted = "[PHONE]"

    # 2. Email check
    if RE_EMAIL_STANDARD.search(raw) or RE_EMAIL_OBFUSCATED.search(raw):
        categories.append("EMAIL_ADDRESS")
        reason_codes.append("DETECTED_EMAIL")
        redacted = RE_EMAIL_STANDARD.sub("[EMAIL]", redacted)
        redacted = RE_EMAIL_OBFUSCATED.sub("[EMAIL]", redacted)

    # 3. URL and IP check
    if RE_URL_STANDARD.search(raw) or RE_URL_DOMAIN.search(raw):
        categories.append("URL")
        categories.append("EXTERNAL_URL")
        reason_codes.append("DETECTED_EXTERNAL_LINK")
        redacted = RE_URL_STANDARD.sub("[URL]", redacted)
        redacted = RE_URL_DOMAIN.sub("[URL]", redacted)

    if RE_URL_OBFUSCATED.search(raw):
        categories.append("OBFUSCATED_URL")
        if "URL" not in categories: categories.append("URL")
        reason_codes.append("DETECTED_OBFUSCATED_LINK")
        redacted = RE_URL_OBFUSCATED.sub("[URL]", redacted)

    if RE_IP_ADDRESS.search(raw):
        categories.append("IP_ADDRESS")
        redacted = RE_IP_ADDRESS.sub("[IP_REDACTED]", redacted)

    # 4. Social handle / Off-platform contact check
    if RE_SOCIAL_HANDLES.search(raw):
        categories.append("SOCIAL_HANDLE")
        reason_codes.append("DETECTED_SOCIAL_TRANSFER")
        redacted = RE_SOCIAL_HANDLES.sub("[SOCIAL_HANDLE_REDACTED]", redacted)

    # 5. Physical address / School location check
    if RE_ADDRESS_SHARING.search(raw):
        categories.append("PHYSICAL_LOCATION")
        reason_codes.append("DETECTED_ADDRESS_SHARING")
        redacted = RE_ADDRESS_SHARING.sub("[ADDRESS_REDACTED]", redacted)

    # 6. Secrecy & grooming cues
    if RE_SECRECY_CUES.search(raw):
        categories.append("GROOMING_SECRECY")
        reason_codes.append("DETECTED_SECRECY_CUE")
        redacted = RE_SECRECY_CUES.sub("[SECRECY_CUE]", redacted)

    detected = len(categories) > 0
    # Any PII detection for under-13 platform is HIGH/CRITICAL severity and policy BLOCK
    severity = "CRITICAL" if ("PHONE_NUMBER" in categories or "PHYSICAL_LOCATION" in categories or "GROOMING_SECRECY" in categories) else ("HIGH" if detected else "LOW")
    policy_action = "BLOCK" if detected else "ALLOW"

    return {
        "detected": detected,
        "categories": categories,
        "severity": severity,
        "policy_action": policy_action,
        "redacted_text": redacted,
        "reason_codes": reason_codes
    }
