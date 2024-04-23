// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


import 'package:file/memory.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/resident_devtools_handler.dart';
import 'package:flutter_tools/src/resident_runner.dart';
import 'package:flutter_tools/src/run_hot.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../../src/common.dart';
import '../../src/context.dart';
import '../../src/fake_vm_services.dart';
import '../../src/fakes.dart';
import '../../src/testbed.dart';
import '../resident_runner_helpers.dart';
import 'fake_native_assets_build_runner.dart';

void main() {
  late Testbed testbed;
  late FakeFlutterDevice flutterDevice;
  late FakeDevFS devFS;
  late ResidentRunner residentRunner;
  late FakeDevice device;
  late FakeAnalytics fakeAnalytics;
  late MemoryFileSystem fileSystem;
  FakeVmServiceHost? fakeVmServiceHost;

  setUp(() {
    fileSystem = MemoryFileSystem.test();

    testbed = Testbed(setup: () {
      fakeAnalytics = getInitializedFakeAnalyticsInstance(
        fs: fileSystem,
        fakeFlutterVersion: FakeFlutterVersion(),
      );

      fileSystem.file('.packages')
        .writeAsStringSync('\n');
      fileSystem.file(fileSystem.path.join('build', 'app.dill'))
        ..createSync(recursive: true)
        ..writeAsStringSync('ABC');
      residentRunner = HotRunner(
        <FlutterDevice>[
          flutterDevice,
        ],
        stayResident: false,
        debuggingOptions: DebuggingOptions.enabled(BuildInfo.debug),
        target: 'main.dart',
        devtoolsHandler: createNoOpHandler,
        analytics: fakeAnalytics,
      );
    });
    device = FakeDevice();
    devFS = FakeDevFS();
    flutterDevice = FakeFlutterDevice()
      ..testUri = testUri
      ..vmServiceHost = (() => fakeVmServiceHost)
      ..device = device
      ..fakeDevFS = devFS;
  });

  testUsingContext(
      'use the nativeAssetsYamlFile when provided',
      () => testbed.run(() async {
        final FakeDevice device = FakeDevice(
          targetPlatform: TargetPlatform.darwin,
          sdkNameAndVersion: 'Macos',
        );
        final FakeResidentCompiler residentCompiler = FakeResidentCompiler();
        final FakeFlutterDevice flutterDevice = FakeFlutterDevice()
          ..testUri = testUri
          ..vmServiceHost = (() => fakeVmServiceHost)
          ..device = device
          ..fakeDevFS = devFS
          ..targetPlatform = TargetPlatform.darwin
          ..generator = residentCompiler;

        fakeVmServiceHost = FakeVmServiceHost(requests: <VmServiceExpectation>[
          listViews,
          listViews,
        ]);
        fileSystem
            .file(fileSystem.path.join('lib', 'main.dart'))
            .createSync(recursive: true);
        final FakeNativeAssetsBuildRunner buildRunner = FakeNativeAssetsBuildRunner();
        residentRunner = HotRunner(
          <FlutterDevice>[
            flutterDevice,
          ],
          stayResident: false,
          debuggingOptions: DebuggingOptions.enabled(const BuildInfo(
            BuildMode.debug,
            '',
            treeShakeIcons: false,
            trackWidgetCreation: true,
          )),
          target: 'main.dart',
          devtoolsHandler: createNoOpHandler,
          nativeAssetsBuilder: FakeHotRunnerNativeAssetsBuilder(buildRunner),
          analytics: fakeAnalytics,
          nativeAssetsYamlFile: 'foo.yaml',
        );

        final int? result = await residentRunner.run();
        expect(result, 0);

        expect(buildRunner.buildInvocations, 0);
        expect(buildRunner.dryRunInvocations, 0);
        expect(buildRunner.hasPackageConfigInvocations, 0);
        expect(buildRunner.packagesWithNativeAssetsInvocations, 0);

        expect(residentCompiler.recompileCalled, true);
        expect(residentCompiler.receivedNativeAssetsYaml, fileSystem.path.toUri('foo.yaml'));
      }),
      overrides: <Type, Generator>{
        ProcessManager: () => FakeProcessManager.any(),
        FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isMacOSEnabled: true),
      });
}
