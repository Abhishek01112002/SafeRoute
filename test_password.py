import re

PASSWORD_REGEX = r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{12,}$"
password = "SecurePass123!@#"
print(f"Password: {password}")
print(f"Length: {len(password)}")
print(f"Has lowercase: {bool(re.search(r'[a-z]', password))}")
print(f"Has uppercase: {bool(re.search(r'[A-Z]', password))}")
print(f"Has digit: {bool(re.search(r'\d', password))}")
print(f"Has special: {bool(re.search(r'[@$!%*?&]', password))}")
print(f"Matches regex: {bool(re.match(PASSWORD_REGEX, password))}")

# Check each character
print(f"\nCharacters: {list(password)}")
for char in password:
    if char in '@$!%*?&':
        print(f"  Special char found: {char}")
