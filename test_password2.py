import re

PASSWORD_REGEX = r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{12,}$"
password = "SecurePass123!@#"

# Test each part of the regex
lookahead1 = re.search(r'(?=.*[a-z])', password)
lookahead2 = re.search(r'(?=.*[A-Z])', password)
lookahead3 = re.search(r'(?=.*\d)', password)
lookahead4 = re.search(r'(?=.*[@$!%*?&])', password)
charset = re.match(r'^[A-Za-z\d@$!%*?&]{12,}$', password)

print(f"Lookahead lowercase: {bool(lookahead1)}")
print(f"Lookahead uppercase: {bool(lookahead2)}")
print(f"Lookahead digit: {bool(lookahead3)}")
print(f"Lookahead special: {bool(lookahead4)}")
print(f"Charset and length: {bool(charset)}")

print(f"\nPassword characters: {list(password)}")
print(f"Allowed charset: A-Za-z 0-9 @$!%*?&")
print(f"# is NOT in allowed charset!")

# Test without the # character
password2 = "SecurePass123!@"
print(f"\nTesting without #: {password2}")
print(f"Matches regex: {bool(re.match(PASSWORD_REGEX, password2))}")
