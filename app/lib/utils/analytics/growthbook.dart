1 import 'dart:io';
2 
3 import 'package:flutter/material.dart';
4 import 'package:friend_private/backend/preferences.dart';
5 import 'package:friend_private/env/env.dart';
6 import 'package:growthbook_sdk_flutter/growthbook_sdk_flutter.dart';
7 
8 class GrowthbookUtil {
9   static final GrowthbookUtil _instance = GrowthbookUtil._internal();
10   static GrowthBookSDK? _gb;
11   static bool isNonWearable = false;
12 
13   factory GrowthbookUtil() {
14     return _instance;
15   }
16 
17   GrowthbookUtil._internal();
18 
19   static Future<void> init() async {
20     if (Env.growthbookApiKey == null) return;
21     var attr = {
22       'id': SharedPreferencesUtil().uid,
23       'device': Platform.isAndroid ? 'android' : 'ios',
24       'isNonWearable': isNonWearable,
25     };
26     _gb = await GBSDKBuilderApp(
27       apiKey: Env.growthbookApiKey!,
28       backgroundSync: true,
29       enable: true,
30       attributes: attr,
31       growthBookTrackingCallBack: (gbExperiment, gbExperimentResult) {
32         debugPrint('growthBookTrackingCallBack: $gbExperiment $gbExperimentResult');
33       },
34       hostURL: 'https://cdn.growthbook.io/',
35       qaMode: true,
36       gbFeatures: {
37         // 'server-transcript': GBFeature(defaultValue: true),
38         'streaming-transcript': GBFeature(defaultValue: false),
39       },
40     ).initialize();
41     _gb!.setAttributes(attr);
42   }
43 
44   bool hasStreamingTranscriptFeatureOn() {
45     if (isNonWearable) {
46       return false;
47     }
48     return true;
49   }
50 }
51 
