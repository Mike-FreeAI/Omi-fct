1 import 'dart:async';
2 import 'dart:convert';
3 import 'dart:io';
4 import 'dart:math';
5 import 'dart:typed_data';
6 
7 import 'package:flutter/material.dart';
8 import 'package:flutter_background_service/flutter_background_service.dart';
9 import 'package:flutter_foreground_task/flutter_foreground_task.dart';
10 import 'package:flutter_provider_utilities/flutter_provider_utilities.dart';
11 import 'package:friend_private/backend/http/api/memories.dart';
12 import 'package:friend_private/backend/http/cloud_storage.dart';
13 import 'package:friend_private/backend/preferences.dart';
14 import 'package:friend_private/backend/schema/bt_device.dart';
15 import 'package:friend_private/backend/schema/geolocation.dart';
16 import 'package:friend_private/backend/schema/memory.dart';
17 import 'package:friend_private/backend/schema/structured.dart';
18 import 'package:friend_private/backend/schema/transcript_segment.dart';
19 import 'package:friend_private/pages/capture/logic/mic_background_service.dart';
20 import 'package:friend_private/pages/capture/logic/openglass_mixin.dart';
21 import 'package:friend_private/pages/capture/logic/websocket_mixin.dart';
22 import 'package:friend_private/providers/memory_provider.dart';
23 import 'package:friend_private/providers/message_provider.dart';
24 import 'package:friend_private/utils/analytics/mixpanel.dart';
25 import 'package:friend_private/utils/audio/wav_bytes.dart';
26 import 'package:friend_private/utils/ble/communication.dart';
27 import 'package:friend_private/utils/enums.dart';
28 import 'package:friend_private/utils/memories/integrations.dart';
29 import 'package:friend_private/utils/memories/process.dart';
30 import 'package:friend_private/utils/websockets.dart';
31 import 'package:permission_handler/permission_handler.dart';
32 import 'package:record/record.dart';
33 import 'package:uuid/uuid.dart';
34 
35 class CaptureProvider extends ChangeNotifier with WebSocketMixin, OpenGlassMixin, MessageNotifierMixin {
36   MemoryProvider? memoryProvider;
37   MessageProvider? messageProvider;
38 
39   void updateProviderInstances(MemoryProvider? mp, MessageProvider? p) {
40     memoryProvider = mp;
41     messageProvider = p;
42   }
43 
44   BTDeviceStruct? connectedDevice;
45   bool isGlasses = false;
46   bool isNonWearable;
47 
48   CaptureProvider({this.isNonWearable = false});
49 
50   bool restartAudioProcessing = false;
51 
52   List<TranscriptSegment> segments = [];
53   Geolocation? geolocation;
54 
55   bool hasTranscripts = false;
56   bool memoryCreating = false;
57   bool webSocketConnected = false;
58   bool webSocketConnecting = false;
59   bool audioBytesConnected = false;
60 
61   static const quietSecondsForMemoryCreation = 120;
62 
63   StreamSubscription? _bleBytesStream;
64 
65   var record = AudioRecorder();
66   RecordingState recordingState = RecordingState.stop;
67 
68 // -----------------------
69 // Memory creation variables
70   double? streamStartedAtSecond;
71   DateTime? firstStreamReceivedAt;
72   int? secondsMissedOnReconnect;
73   WavBytesUtil? audioStorage;
74   Timer? _memoryCreationTimer;
75   String conversationId = const Uuid().v4();
76   DateTime? currentTranscriptStartedAt;
77   DateTime? currentTranscriptFinishedAt;
78   int elapsedSeconds = 0;
79 
80   // -----------------------
81 
82   void setHasTranscripts(bool value) {
83     hasTranscripts = value;
84     notifyListeners();
85   }
86 
87   void setMemoryCreating(bool value) {
88     memoryCreating = value;
89     notifyListeners();
90   }
91 
92   void setGeolocation(Geolocation? value) {
93     geolocation = value;
94     notifyListeners();
95   }
96 
97   void setWebSocketConnected(bool value) {
98     webSocketConnected = value;
99     notifyListeners();
100   }
101 
102   void setWebSocketConnecting(bool value) {
103     webSocketConnecting = value;
104     notifyListeners();
105   }
106 
107   void setAudioBytesConnected(bool value) {
108     audioBytesConnected = value;
109     notifyListeners();
110   }
111 
112   void updateConnectedDevice(BTDeviceStruct? device) {
113     debugPrint('connected device changed from ${connectedDevice?.id} to ${device?.id}');
114     connectedDevice = device;
115     notifyListeners();
116   }
117 
118   Future<bool?> createMemory({bool forcedCreation = false}) async {
119     debugPrint('_createMemory forcedCreation: $forcedCreation');
120     if (memoryCreating) return null;
121     if (segments.isEmpty && photos.isEmpty) return false;
122 
123     // TODO: should clean variables here? and keep them locally?
124     setMemoryCreating(true);
125     File? file;
126     if (audioStorage?.frames.isNotEmpty == true) {
127       try {
128         var secs = !forcedCreation ? quietSecondsForMemoryCreation : 0;
129         file = (await audioStorage!.createWavFile(removeLastNSeconds: secs)).item1;
130         uploadFile(file);
131       } catch (e) {
132         print("creating and uploading file error: $e");
133       } // in case was a local recording and not a BLE recording
134     }
135 
136     ServerMemory? memory = await processTranscriptContent(
137       segments: segments,
138       startedAt: currentTranscriptStartedAt,
139       finishedAt: currentTranscriptFinishedAt,
140       geolocation: geolocation,
141       photos: photos,
142       sendMessageToChat: (v) {
143         // use message provider to send message to chat
144         messageProvider?.addMessage(v);
145       },
146       triggerIntegrations: true,
147       language: SharedPreferencesUtil().recordingsLanguage,
148       audioFile: file,
149     );
150     debugPrint(memory.toString());
151     if (memory == null && (segments.isNotEmpty || photos.isNotEmpty)) {
152       memory = ServerMemory(
153         id: const Uuid().v4(),
154         createdAt: DateTime.now(),
155         structured: Structured('', '', emoji: '⛓️‍💥', category: 'other'),
156         discarded: true,
157         transcriptSegments: segments,
158         geolocation: geolocation,
159         photos: photos.map<MemoryPhoto>((e) => MemoryPhoto(e.item1, e.item2)).toList(),
160         startedAt: currentTranscriptStartedAt,
161         finishedAt: currentTranscriptFinishedAt,
162         failed: true,
163         source: segments.isNotEmpty ? MemorySource.friend : MemorySource.openglass,
164         language: segments.isNotEmpty ? SharedPreferencesUtil().recordingsLanguage : null,
165       );
166       SharedPreferencesUtil().addFailedMemory(memory);
167 
168       // TODO: store anyways something temporal and retry once connected again.
169     }
170 
171     if (memory != null) {
172       // use memory provider to add memory
173       MixpanelManager().memoryCreated(memory);
174       memoryProvider?.addMemory(memory);
175       if (memoryProvider?.memories.isEmpty ?? false) {
176         memoryProvider?.getMoreMemoriesFromServer();
177       }
178     }
179 
180     if (memory != null && !memory.failed && file != null && segments.isNotEmpty && !memory.discarded) {
181       setMemoryCreating(false);
182       try {
183         memoryPostProcessing(file, memory.id).then((postProcessed) {
184           if (postProcessed != null) {
185             memoryProvider?.updateMemory(postProcessed);
186           } else {
187             memory!.postprocessing = MemoryPostProcessing(
188               status: MemoryPostProcessingStatus.failed,
189               model: MemoryPostProcessingModel.fal_whisperx,
190             );
191             memoryProvider?.updateMemory(memory);
192           }
193         });
194       } catch (e) {
195         print('Error occurred during memory post-processing: $e');
196       }
197     }
198 
199     SharedPreferencesUtil().transcriptSegments = [];
200     segments = [];
201     audioStorage?.clearAudioBytes();
202     setHasTranscripts(false);
203 
204     currentTranscriptStartedAt = null;
205     currentTranscriptFinishedAt = null;
206     elapsedSeconds = 0;
207 
208     streamStartedAtSecond = null;
209     firstStreamReceivedAt = null;
210     secondsMissedOnReconnect = null;
211     photos = [];
212     conversationId = const Uuid().v4();
213     setMemoryCreating(false);
214     notifyListeners();
215     return true;
216   }
217 
218   Future<void> initiateWebsocket([
219     BleAudioCodec? audioCodec,
220     int? sampleRate,
221   ]) async {
222     if (isNonWearable) {
223       return;
224     }
225     setWebSocketConnecting(true);
226     print('initiateWebsocket');
227     BleAudioCodec codec = audioCodec ?? SharedPreferencesUtil().deviceCodec;
228     sampleRate ??= (codec == BleAudioCodec.opus ? 16000 : 8000);
229     await initWebSocket(
230       codec: codec,
231       sampleRate: sampleRate,
232       includeSpeechProfile: false,
233       onConnectionSuccess: () {
234         print('inside onConnectionSuccess');
235         setWebSocketConnecting(false);
236         setWebSocketConnected(true);
237         if (segments.isNotEmpty) {
238           // means that it was a reconnection, so we need to reset
239           streamStartedAtSecond = null;
240           secondsMissedOnReconnect = (DateTime.now().difference(firstStreamReceivedAt!).inSeconds);
241         }
242         notifyListeners();
243       },
244       onConnectionFailed: (err) {
245         notifyListeners();
246       },
247       onConnectionClosed: (int? closeCode, String? closeReason) {
248         print('inside onConnectionClosed');
249         print('closeCode: $closeCode');
250         // connection was closed, either on resetState, or by backend, or by some other reason.
251         // setState(() {});
252       },
253       onConnectionError: (err) {
254         print('inside onConnectionError');
255         print('err: $err');
256         // connection was okay, but then failed.
257         notifyListeners();
258       },
259       onMessageReceived: (List<TranscriptSegment> newSegments) {
260         if (newSegments.isEmpty) return;
261         if (segments.isEmpty) {
262           debugPrint('newSegments: ${newSegments.last}');
263           // TODO: small bug -> when memory A creates, and memory B starts, memory B will clean a lot more seconds than available,
264           //  losing from the audio the first part of the recording. All other parts are fine.
265           FlutterForegroundTask.sendDataToTask(jsonEncode({'location': true}));
266           var currentSeconds = (audioStorage?.frames.length ?? 0) ~/ 100;
267           var removeUpToSecond = newSegments[0].start.toInt();
268           audioStorage?.removeFramesRange(fromSecond: 0, toSecond: min(max(currentSeconds - 5, 0), removeUpToSecond));
269           firstStreamReceivedAt = DateTime.now();
270         }
271         streamStartedAtSecond ??= newSegments[0].start;
272 
273         TranscriptSegment.combineSegments(
274           segments,
275           newSegments,
276           toRemoveSeconds: streamStartedAtSecond ?? 0,
277           toAddSeconds: secondsMissedOnReconnect ?? 0,
278         );
279         triggerTranscriptSegmentReceivedEvents(newSegments, conversationId, sendMessageToChat: (v) {
280           messageProvider?.addMessage(v);
281         });
282         SharedPreferencesUtil().transcriptSegments = segments;
283         setHasTranscripts(true);
284         debugPrint('Memory creation timer restarted');
285         _memoryCreationTimer?.cancel();
286         _memoryCreationTimer = Timer(const Duration(seconds: quietSecondsForMemoryCreation), () => createMemory());
287         currentTranscriptStartedAt ??= DateTime.now();
288         currentTranscriptFinishedAt = DateTime.now();
289         notifyListeners();
290       },
291     );
292   }
293 
294   Future streamAudioToWs(String id, BleAudioCodec codec) async {
295     if (isNonWearable) {
296       return;
297     }
298     print('streamAudioToWs');
299     audioStorage = WavBytesUtil(codec: codec);
300     if (_bleBytesStream != null) {
301       _bleBytesStream?.cancel();
302     }
303     _bleBytesStream = await getBleAudioBytesListener(
304       id,
305       onAudioBytesReceived: (List<int> value) {
306         if (value.isEmpty) return;
307         audioStorage!.storeFramePacket(value);
308         // print(value);
309         final trimmedValue = value.sublist(3);
310         // TODO: if this (0,3) is not removed, deepgram can't seem to be able to detect the audio.
311         // https://developers.deepgram.com/docs/determining-your-audio-format-for-live-streaming-audio
312         if (wsConnectionState == WebsocketConnectionStatus.connected) {
313           websocketChannel?.sink.add(trimmedValue);
314         }
315       },
316     );
317     setAudioBytesConnected(true);
318     notifyListeners();
319   }
320 
321   void setRestartAudioProcessing(bool value) {
322     restartAudioProcessing = value;
323     notifyListeners();
324   }
325 
326   Future resetState({bool restartBytesProcessing = true, BTDeviceStruct? btDevice}) async {
327     //TODO: Improve this, do not rely on the captureKey. And also get rid of global keys if possible.
328     debugPrint('resetState: $restartBytesProcessing');
329     closeBleStream();
330     cancelMemoryCreationTimer();
331 
332     if (!restartBytesProcessing && (segments.isNotEmpty || photos.isNotEmpty)) {
333       var res = await createMemory(forcedCreation: true);
334       notifyListeners();
335       if (res != null && !res) {
336         notifyError('Memory creation failed. It\' stored locally and will be retried soon.');
337       } else {
338         notifyInfo('Memory created successfully 🚀');
339       }
340     }
341     if (restartBytesProcessing) {
342       if (webSocketConnected) {
343         closeWebSocket();
344         await initiateWebsocket();
345       } else {
346         await initiateWebsocket();
347       }
348     } else {
349       closeWebSocket();
350     }
351     setRestartAudioProcessing(restartBytesProcessing);
352     startOpenGlass();
353     initiateFriendAudioStreaming();
354     notifyListeners();
355   }
356 
357   processCachedTranscript() async {
358     // TODO: only applies to friend, not openglass, fix it
359     var segments = SharedPreferencesUtil().transcriptSegments;
360     if (segments.isEmpty) return;
361     processTranscriptContent(
362       segments: segments,
363       sendMessageToChat: null,
364       triggerIntegrations: false,
365       language: SharedPreferencesUtil().recordingsLanguage,
366     );
367     SharedPreferencesUtil().transcriptSegments = [];
368     // TODO: include created at and finished at for this cached transcript
369   }
370 
371   Future<void> startOpenGlass() async {
372     if (connectedDevice == null) return;
373     isGlasses = await hasPhotoStreamingCharacteristic(connectedDevice!.id);
374     if (!isGlasses) return;
375     await openGlassProcessing(connectedDevice!, (p) {}, setHasTranscripts);
376     closeWebSocket();
377     notifyListeners();
378   }
379 
380   Future<void> initiateFriendAudioStreaming() async {
381     print('inside initiateFriendAudioStreaming');
382     if (connectedDevice == null) return;
383     BleAudioCodec codec = await getAudioCodec(connectedDevice!.id);
384     if (SharedPreferencesUtil().deviceCodec != codec) {
385       debugPrint('Device codec changed from ${SharedPreferencesUtil().deviceCodec} to $codec');
386       SharedPreferencesUtil().deviceCodec = codec;
387       notifyInfo('FIM_CHANGE');
388     } else {
389       if (audioBytesConnected) return;
390       streamAudioToWs(connectedDevice!.id, codec);
391     }
392 
393     notifyListeners();
394   }
395 
396   void closeBleStream() {
397     _bleBytesStream?.cancel();
398     notifyListeners();
399   }
400 
401   void cancelMemoryCreationTimer() {
402     _memoryCreationTimer?.cancel();
403     notifyListeners();
404   }
405 
406   @override
407   void dispose() {
408     _bleBytesStream?.cancel();
409     _memoryCreationTimer?.cancel();
410     super.dispose();
411   }
412 
413   void updateRecordingState(RecordingState state) {
414     recordingState = state;
415     notifyListeners();
416   }
417 
418   startStreamRecording() async {
419     await Permission.microphone.request();
420     var stream = await record.startStream(
421       const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
422     );
423     updateRecordingState(RecordingState.record);
424     stream.listen((data) async {
425       if (wsConnectionState == WebsocketConnectionStatus.connected) {
426         websocketChannel?.sink.add(data);
427       }
428     });
429   }
430 
431   streamRecordingOnAndroid() async {
432     await Permission.microphone.request();
433     updateRecordingState(RecordingState.initialising);
434     await initializeMicBackgroundService();
435     startBackgroundService();
436     await listenToBackgroundService();
437   }
438 
439   listenToBackgroundService() async {
440     if (await FlutterBackgroundService().isRunning()) {
441       FlutterBackgroundService().on('audioBytes').listen((event) {
442         Uint8List convertedList = Uint8List.fromList(event!['data'].cast<int>());
443         if (wsConnectionState == WebsocketConnectionStatus.connected) websocketChannel?.sink.add(convertedList);
444       });
445       FlutterBackgroundService().on('stateUpdate').listen((event) {
446         if (event!['state'] == 'recording') {
447           updateRecordingState(RecordingState.record);
448         } else if (event['state'] == 'initializing') {
449           updateRecordingState(RecordingState.initialising);
450         } else if (event['state'] == 'stopped') {
451           updateRecordingState(RecordingState.stop);
452         }
453       });
454     }
455   }
456 
457   stopStreamRecording() async {
458     if (await record.isRecording()) await record.stop();
459     updateRecordingState(RecordingState.stop);
460     notifyListeners();
461   }
462 
463   stopStreamRecordingOnAndroid() {
464     stopBackgroundService();
465   }
466 }
