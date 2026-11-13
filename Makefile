# Photos Backup Tracker: build, test, install.
.PHONY: help test test-python test-swift test-e2e screenshots app dmg install uninstall

APP_BUILD_FOLDER ?= $(HOME)/Library/Caches/photos-backup-tracker/app

help:
	@echo "make test        run the Python and Swift tests against the current source"
	@echo "make test-e2e    run the end-to-end tests (set PHOTOS_BACKUP_E2E_TARGET to your backup folder)"
	@echo "make screenshots regenerate the README screenshots (docs/screenshots) from demo data"
	@echo "make app         build Photos Backup Tracker.app into $(APP_BUILD_FOLDER)"
	@echo "make dmg         package the app as a drag-to-install .dmg for distribution"
	@echo "make install     build the app and install it into /Applications"
	@echo "make uninstall   remove both again"

test: test-python test-swift

test-python:
	uv run pytest

test-swift:
	app/test.sh

test-e2e:
	uv run pytest -m e2e -v

screenshots:
	PHOTOS_BACKUP_SCREENSHOTS_FOLDER="$(CURDIR)/docs/screenshots" app/test.sh --filter ScreenshotTests

app:
	app/build.sh "$(APP_BUILD_FOLDER)"

dmg:
	scripts/package-dmg.sh

install:
	scripts/install.sh

uninstall:
	scripts/uninstall.sh
