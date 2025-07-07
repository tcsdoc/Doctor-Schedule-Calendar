# Doctor Schedule Calendar - Development Guide

## Project Roadmap

### Phase 1: Foundation ✅
- [x] Initial Xcode project setup
- [x] Core Data integration
- [x] Basic SwiftUI structure
- [x] Fix bundle identifier

### Phase 2: Core Features (Upcoming)
- [ ] Create Doctor entity in Core Data model
- [ ] Create Appointment entity with relationships
- [ ] Design calendar UI components
- [ ] Implement appointment creation
- [ ] Add appointment editing/deletion

### Phase 3: Enhanced Features
- [ ] Patient management
- [ ] Appointment scheduling logic
- [ ] Notification system
- [ ] Export/import functionality

### Phase 4: Polish & Testing
- [ ] Comprehensive unit tests
- [ ] UI tests for critical flows
- [ ] Performance optimization
- [ ] Accessibility improvements

## Development Workflow

### Branch Strategy
```bash
# Create feature branches for new work
git checkout -b feature/doctor-management
git checkout -b feature/calendar-ui
git checkout -b bugfix/appointment-validation
```

### Commit Message Format
```
feat: add doctor profile management
fix: resolve calendar date display issue
docs: update installation instructions
test: add unit tests for appointment creation
```

### Version Tagging
```bash
# Create version tags for releases
git tag -a v0.1.0 -m "Initial working prototype"
git tag -a v1.0.0 -m "First release with basic scheduling"
```

## Development Commands

### Useful Git Aliases
```bash
git config alias.hist "log --oneline --graph --decorate --all"
git config alias.last "log -1 HEAD --stat"
git config alias.unstage "reset HEAD --"
```

### Project Status Commands
```bash
# Quick project overview
git log --oneline -10
git status
git diff --name-only

# Detailed change analysis
git show --stat
git log --since="1 week ago" --oneline
```

## Code Review Checklist
- [ ] Core Data relationships properly defined
- [ ] SwiftUI preview working
- [ ] No force unwrapping (!)
- [ ] Proper error handling
- [ ] Tests added for new functionality
- [ ] Documentation updated 