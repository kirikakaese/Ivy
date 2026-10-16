SCHEME=Signal
PODS=Pods
BACKUP_TESTS=SignalServiceKit/tests/MessageBackup/Signal-Message-Backup-Tests

.PHONY: dependencies
dependencies: pod-setup backup-tests-setup fetch-ringrtc

.PHONY: pod-setup
pod-setup:
	bundle install
	bundle exec pod install

.PHONY: backup-tests-setup
backup-tests-setup:
	git submodule update --init --progress ${BACKUP_TESTS}

.PHONY: fetch-ringrtc
fetch-ringrtc:
	$(CURDIR)/Pods/SignalRingRTC/bin/set-up-for-cocoapods
