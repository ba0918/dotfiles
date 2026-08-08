from detect_secret import is_example_path, scan


def test_clean_code_no_findings():
    assert scan("def hello():\n    return 'world'", "hello.py") == []


def test_aws_access_key():
    findings = scan("aws_key = AKIAIOSFODNN7EXAMPLE", "config.py")
    assert any("AWS" in f.kind for f in findings)


def test_aws_session_key():
    findings = scan("tok = ASIAIOSFODNN7EXAMPLE", "config.py")
    assert any("AWS" in f.kind for f in findings)


def test_github_token():
    findings = scan("GITHUB_TOKEN=ghp_" + "a" * 36, "app.env")
    assert any("GitHub" in f.kind for f in findings)


def test_anthropic_api_key():
    findings = scan("key = 'sk-ant-api03-" + "a" * 95 + "'", "config.py")
    assert any("Anthropic" in f.kind for f in findings)


def test_openai_api_key_not_anthropic():
    findings = scan("key = 'sk-" + "a" * 48 + "'", "config.py")
    kinds = [f.kind for f in findings]
    assert any("OpenAI" in k for k in kinds)
    assert not any("Anthropic" in k for k in kinds)


def test_google_api_key():
    findings = scan("key = AIza" + "A" * 35, "config.py")
    assert any("Google" in f.kind for f in findings)


def test_slack_token():
    findings = scan("tok = xoxb-1234567890-abcdefg", "config.py")
    assert any("Slack" in f.kind for f in findings)


def test_jwt():
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    findings = scan(f"token = '{jwt}'", "api.js")
    assert any("JWT" in f.kind for f in findings)


def test_pem_private_key():
    findings = scan("-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n", "key.pem")
    assert any("PEM" in f.kind for f in findings)


def test_pem_openssh_private_key():
    findings = scan("-----BEGIN OPENSSH PRIVATE KEY-----\n...", "id_rsa")
    assert any("PEM" in f.kind for f in findings)


def test_generic_password_assignment():
    findings = scan("password = 'S3cr3tV@lueL0ngEnough1234'", "config.py")
    assert any("generic" in f.kind for f in findings)


def test_generic_api_key_assignment():
    findings = scan("api_key: 'abcdef1234567890abcdef1234567890'", "config.yaml")
    assert any("generic" in f.kind for f in findings)


def test_example_path_ignored():
    assert scan("api_key = AKIAIOSFODNN7EXAMPLE", ".env.example") == []


def test_sample_path_ignored():
    assert scan("api_key = AKIAIOSFODNN7EXAMPLE", "config.sample.json") == []


def test_placeholder_value_ignored():
    assert scan("api_key = 'your_api_key_here_1234567890'", "README.md") == []


def test_angle_bracket_placeholder_ignored():
    assert scan("api_key = <your_api_key>", "docs.md") == []


def test_version_string_not_flagged():
    # generic pattern requires key words (api_key/secret/etc); versions rarely match
    assert scan("version: '1.2.3'", "pyproject.toml") == []


def test_redacts_long_lines():
    long_line = "password = '" + "a" * 200 + "'"
    findings = scan(long_line, "config.py")
    assert findings and len(findings[0].snippet) <= 125


def test_is_example_path():
    assert is_example_path(".env.example")
    assert is_example_path("config.example.json")
    assert is_example_path("sample.env")
    assert is_example_path("docker-compose.template.yml")
    assert not is_example_path("config.env")
    assert not is_example_path("production.py")


def test_reports_correct_line_number():
    text = "line1\nline2\nakey = ghp_" + "a" * 36
    findings = scan(text, "x.txt")
    assert any(f.line_no == 3 for f in findings)
