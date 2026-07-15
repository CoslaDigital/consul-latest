# Changelog

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## What's Changed

## [2.5.1-local.1](https://github.com/cosladigital/consul-latest/tree/2.5.1-local.1) (2026-7-15)

### Added

* Add kind to Proposals to allow filtering of proposals by type
* Add filter to Proposals Admin to show proposals by kind
* Ai moderation
* Link to custom documentation added to Admin dash
* Auto create milestones when mutual aid phase changes
* Add milestone status link to admin menu

### Changed

* change behaviour of mapping add accessibilty and auto bounds to map
* add terrain and satellite base layers to map
* improved behaviour of import users rake script
* add updated_at to proposals admin table view
* improvements to Mutual Aid dashboard and emails

### Fixed

* Enforce Ownership Isolation for Process Managers (Budgets & Legislation) - process managers can only manage their own
  processes
* Update custom branding for efficiency

* [Full Changelog:](https://github.com/CoslaDigital/consul-latest/compare/v2.4.1-local-4...2.5.1-local.1)

## [2.4.1-local.4](https://github.com/cosladigital/consul-latest/tree/2.4.1-local.4) (2026-5-5)

### Added
* Add pexel image suggestions
* Milestones: Allow proposal owners to manage Milestones
* Mutual Aid: Mutual Aid module in https://github.com/CoslaDigital/consul-latest/pull/150
* Sentiment Analysis: Added Sentiment analysis to comments in Machine Learning code
* Sensemaking: added experimental sensemaking code to analyse processes using AI
* Security:  obfuscate usernames in comments 
* Security: allow use of 2 Factor Authentication and add feature switch to force for admins
* Feature: Add feature setting to restrict debate creation to Admin only
* Feature: Give users ability to make documents private
* Add user lock/unlock functionality to admin users index
* Feature: add voter density auditing and spatial analysis for budget balloting
### Changed
* Display results on Admin poll results page
* Replace python Machine Learning scripts with integrated ruby code using RubyLLM
* Proposals: add published/draft to Admin view 
### Fixed
* restore custom proposals download
*  make invalid geozone error user friendly

**Full Changelog**: https://github.com/CoslaDigital/consul-latest/commits/v2.4.1-local.2

## [2.4.1-local.1](https://github.com/cosladigital/consul-latest/tree/2.4.1-local.1) (2025-12-23)

### Added

* Feature: make it possible to move cards between pages
* Feature: add events calendar
* Feature: add homepage upcoming events widget
* Feature: add ability to login using an ID card number
* Feature:add csv download to proposals

### Changed

* Refactor: Update layout of Sign in and Registration pages to improve messaging for myaccount and young scot
* Feature: Send notification to admin address when proposal published
* Refactor: proposals form
* update registration page to break organisation out from individual sign up
* Refactor: changed to size and rendering of the homepage header image

### Fixed

* Add correct currency to proposals
* Display correct currency symbol for budget in dossier
* Improve image rendering on proposals and investments
* Improved mobile layout for proposals

### Full Changelog: https://github.com/CoslaDigital/consul-latest/compare/v2.3.1-local.4...v2.4.1-local.1

## [2.3.1-local.4](https://github.com/cosladigital/consul-latest/tree/2.3.1-local.4) (2025-08-01)

### Added
- add ability to create and manage optional custom questions in budgets

### Changed
- add summary and description fields to budget investments exporter

### Fixed


## [2.3.1-local.3](https://github.com/cosladigital/consul-latest/tree/2.3.1-local.3) (2025-07-03)

### Added
- add feature switch to hide dashboard progress graph 
- display version information from CHANGELOG-LOCAL.md

### Changed
- Refactor to add url to release in Admin dashboard

### Fixed
- Display correct currency symbol for budget in dossier 
- display formatted price for proposals 
- **fix:** typo in edit dossier form causing 500 error 
- **Fix:** fixed bug in registration form for organizations


## [2.3.1-local.2](https://github.com/cosladigital/consul-latest/tree/2.3.1-local.2) (2025-06-13)

### Added

### Changed

### Fixed
- **Fix:** fixed bug in registration form for organizations

## [2.3.1-local.1](https://github.com/cosladigital/consul-latest/tree/2.3.1-local.1) (2025-06-03)

[Base Changelog](https://github.com/consuldemocracy/consuldemocracy/compare/2.3.0...2.3.1)

### Added

- **Feature:** Admins can manually set a Budget Investment Proposal as a winner
- **Feature:** Version information now displayed on Admin dashboard
- **Feature:** Send notification to Admin when an organisation registers
- **Feature:** Added Process manager role which cn create/manage processes
- **Feature** Added local change log

### Changed

### Fixed
