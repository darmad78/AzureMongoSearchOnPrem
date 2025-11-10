# Contributing to MongoDB Enterprise Advanced Document Search App

Thank you for your interest in contributing to this project! This document provides guidelines and information for contributors.

## 🤝 How to Contribute

### Reporting Issues

1. **Check existing issues** - Make sure the issue hasn't already been reported
2. **Use the issue template** - Provide clear, detailed information
3. **Include system information** - OS, Kubernetes version, MongoDB version
4. **Provide steps to reproduce** - Help us understand the problem

### Suggesting Enhancements

1. **Check existing discussions** - See if your idea has been discussed
2. **Provide detailed description** - Explain the enhancement and its benefits
3. **Consider implementation** - Think about how it might be implemented
4. **Be open to feedback** - Discuss and refine your ideas

### Code Contributions

1. **Fork the repository**
2. **Create a feature branch**
3. **Make your changes**
4. **Test thoroughly**
5. **Submit a pull request**

## 🚀 Development Setup

### Prerequisites

- Kubernetes cluster (minikube, kind, or Docker Desktop)
- kubectl
- Helm
- Docker
- Python 3.8+
- Node.js 16+

### Local Development

```bash
# Clone your fork
git clone https://github.com/yourusername/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem

# Set up development environment
cp deploy.conf.example deploy.conf
# Edit deploy.conf with your settings

# Deploy MongoDB Enterprise Advanced
./deploy.sh

# Start backend development server
cd backend
pip install -r requirements.txt
python main.py

# Start frontend development server (in another terminal)
cd frontend
npm install
npm run dev
```

## 📝 Coding Standards

### Python (Backend)

- Follow PEP 8 style guidelines
- Use type hints where possible
- Write docstrings for functions and classes
- Use meaningful variable names
- Handle errors gracefully

```python
def search_documents(query: str) -> List[Document]:
    """
    Search for documents using MongoDB text search.
    
    Args:
        query: Search query string
        
    Returns:
        List of matching documents
        
    Raises:
        DatabaseError: If search fails
    """
    try:
        # Implementation here
        pass
    except Exception as e:
        logger.error(f"Search failed: {e}")
        raise DatabaseError(f"Search operation failed: {e}")
```

### JavaScript/React (Frontend)

- Use functional components with hooks
- Follow React best practices
- Use meaningful component names
- Handle loading and error states
- Use consistent formatting

```javascript
const DocumentSearch = ({ onSearch }) => {
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSearch = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    
    try {
      await onSearch(query);
    } catch (err) {
      setError('Search failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSearch}>
      {/* Component JSX */}
    </form>
  );
};
```

### Shell Scripts

- Use `set -e` for error handling
- Use meaningful variable names
- Add comments for complex logic
- Use consistent indentation
- Handle errors gracefully

```bash
#!/bin/bash
set -e

# Configuration
MONGODB_VERSION="8.2.1-ent"
NAMESPACE="mongodb"

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    command -v kubectl &> /dev/null || missing_tools+=("kubectl")
    command -v helm &> /dev/null || missing_tools+=("helm")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "❌ Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}
```

## 🧪 Testing

### Backend Testing

```bash
cd backend
pip install pytest pytest-asyncio
pytest tests/
```

### Frontend Testing

```bash
cd frontend
npm install
npm test
```

### Integration Testing

```bash
# Deploy test environment
./deploy.sh

# Run integration tests
./tests/integration-test.sh
```

## 📋 Pull Request Process

### Before Submitting

1. **Test your changes** - Ensure everything works
2. **Update documentation** - Update relevant docs
3. **Check formatting** - Follow coding standards
4. **Write tests** - Add tests for new features
5. **Update CHANGELOG** - Document your changes

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

## 🏷️ Commit Messages

Use clear, descriptive commit messages:

```
feat: add MongoDB Search integration
fix: resolve connection string parsing issue
docs: update deployment instructions
test: add integration tests for search API
refactor: improve error handling in backend
```

## 📚 Documentation

### Code Documentation

- Write clear docstrings for functions and classes
- Include examples in documentation
- Update README files for new features
- Document configuration options

### API Documentation

- Update API endpoint documentation
- Include request/response examples
- Document error codes and messages
- Keep OpenAPI spec updated

## 🔍 Code Review

### Review Guidelines

- **Functionality** - Does it work as expected?
- **Code quality** - Is it well-written and maintainable?
- **Performance** - Are there any performance concerns?
- **Security** - Are there any security issues?
- **Testing** - Are there adequate tests?

### Review Process

1. **Automated checks** - CI/CD pipeline runs
2. **Code review** - At least one reviewer required
3. **Testing** - Verify tests pass
4. **Documentation** - Check docs are updated
5. **Approval** - Merge after approval

## 🚫 What Not to Contribute

- **Sensitive information** - No passwords, keys, or secrets
- **Large files** - Use Git LFS for large files
- **Breaking changes** - Discuss major changes first
- **Unrelated features** - Keep PRs focused

## 📞 Getting Help

- **GitHub Issues** - For bug reports and feature requests
- **GitHub Discussions** - For questions and general discussion
- **Documentation** - Check existing docs first
- **Community** - Join our community discussions

## 🎉 Recognition

Contributors will be recognized in:
- README.md contributors section
- Release notes
- Community highlights

Thank you for contributing to this project! 🚀







