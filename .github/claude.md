# .github

## Purpose

GitHub repository configuration for issues, pull requests, and contribution guidelines.

## Contents

```
.github/
├── ISSUE_TEMPLATE/           # Issue templates
│   ├── bug_report.md         # Bug report structure
│   ├── config.yml            # Template configuration
│   └── ISSUE_TEMPLATE.md     # General issue template
├── PULL_REQUEST_TEMPLATE/    # PR templates
│   └── pull_request_template.md
├── CONTRIBUTING.md           # Contribution guidelines
└── PULL_REQUEST_TEMPLATE.md  # Root PR template
```

## Usage

### Issue Templates

When users create issues, GitHub provides structured templates:
- **Bug Report** - Systematic bug reporting with steps to reproduce
- **General Issue** - Standard issue template

### Pull Request Templates

PRs are automatically populated with:
- Checklist for PR requirements
- Guidelines for contribution
- Links to documentation

### Contributing Guidelines

`CONTRIBUTING.md` contains:
- Development guidelines
- Code style requirements
- Legal disclaimer about providers
- Testing requirements

## Important Notes

- All contributions must follow the non-commercial license
- Provider addons must not link to illegal content
- Code must pass flake8 linting
- Translations should be validated with scripts
