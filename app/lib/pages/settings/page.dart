1 import 'package:flutter/material.dart';
2 import 'package:flutter/services.dart';
3 import 'package:friend_private/backend/preferences.dart';
4 import 'package:friend_private/pages/plugins/page.dart';
5 import 'package:friend_private/pages/settings/calendar.dart';
6 import 'package:friend_private/pages/settings/developer.dart';
7 import 'package:friend_private/pages/settings/people.dart';
8 import 'package:friend_private/pages/settings/privacy.dart';
9 import 'package:friend_private/pages/settings/recordings_storage_permission.dart';
10 import 'package:friend_private/pages/settings/webview.dart';
11 import 'package:friend_private/pages/settings/widgets.dart';
12 import 'package:friend_private/pages/speaker_id/page.dart';
13 import 'package:friend_private/utils/analytics/mixpanel.dart';
14 import 'package:friend_private/utils/other/temp.dart';
15 import 'package:friend_private/widgets/dialog.dart';
16 import 'package:gradient_borders/gradient_borders.dart';
17 import 'package:package_info_plus/package_info_plus.dart';
18 import 'package:url_launcher/url_launcher.dart';
19 
20 class SettingsPage extends StatefulWidget {
21   final bool isNonWearable;
22 
23   const SettingsPage({super.key, this.isNonWearable = false});
24 
25   @override
26   State<SettingsPage> createState() => _SettingsPageState();
27 }
28 
29 class _SettingsPageState extends State<SettingsPage> {
30   late String _selectedLanguage;
31   late bool optInAnalytics;
32   late bool optInEmotionalFeedback;
33   late bool devModeEnabled;
34   String? version;
35   String? buildVersion;
36 
37   @override
38   void initState() {
39     _selectedLanguage = SharedPreferencesUtil().recordingsLanguage;
40     optInAnalytics = SharedPreferencesUtil().optInAnalytics;
41     optInEmotionalFeedback = SharedPreferencesUtil().optInEmotionalFeedback;
42     devModeEnabled = SharedPreferencesUtil().devModeEnabled;
43     PackageInfo.fromPlatform().then((PackageInfo packageInfo) {
44       version = packageInfo.version;
45       buildVersion = packageInfo.buildNumber.toString();
46       setState(() {});
47     });
48     super.initState();
49   }
50 
51   bool loadingExportMemories = false;
52 
53   @override
54   Widget build(BuildContext context) {
55     Future<void> _showMockupOmiFeebackNotification() async {
56       showDialog(
57         context: context,
58         builder: (BuildContext context) {
59           return Dialog(
60             shape: RoundedRectangleBorder(
61               borderRadius: BorderRadius.circular(12.0),
62             ),
63             elevation: 5.0,
64             backgroundColor: Colors.black,
65             child: Container(
66               padding: const EdgeInsets.all(20.0),
67               decoration: BoxDecoration(
68                 border: const GradientBoxBorder(
69                   gradient: LinearGradient(colors: [
70                     Color.fromARGB(127, 208, 208, 208),
71                     Color.fromARGB(127, 188, 99, 121),
72                     Color.fromARGB(127, 86, 101, 182),
73                     Color.fromARGB(127, 126, 190, 236)
74                   ]),
75                   width: 2,
76                 ),
77                 borderRadius: BorderRadius.circular(12),
78               ),
79               child: Column(
80                 mainAxisSize: MainAxisSize.min,
81                 children: [
82                   const _MockNotification(
83                     path: 'assets/images/emotional_feedback_1.png',
84                   ),
85                   const SizedBox(
86                     height: 25,
87                   ),
88                   const Text(
89                     "Omi will send you feedback in real-time.",
90                     textAlign: TextAlign.center,
91                     style: TextStyle(color: Color.fromRGBO(255, 255, 255, .8)),
92                   ),
93                   const SizedBox(
94                     height: 25,
95                   ),
96                   Container(
97                     padding: const EdgeInsets.only(
98                       left: 8,
99                       right: 8,
100                       top: 8,
101                       bottom: 8,
102                     ),
103                     child: TextButton(
104                       style: TextButton.styleFrom(
105                         padding: EdgeInsets.zero,
106                         minimumSize: const Size(50, 30),
107                         tapTargetSize: MaterialTapTargetSize.shrinkWrap,
108                         alignment: Alignment.center,
109                       ),
110                       child: const Text(
111                         "Ok, I understand",
112                         textAlign: TextAlign.center,
113                         style: TextStyle(
114                           color: Color.fromRGBO(255, 255, 255, .8),
115                           fontWeight: FontWeight.bold,
116                         ),
117                       ),
118                       onPressed: () {
119                         Navigator.of(context).pop();
120                       },
121                     ),
122                   ),
123                 ],
124               ),
125             ),
126           );
127         },
128       );
129     }
130 
131     return PopScope(
132         canPop: true,
133         child: Scaffold(
134           backgroundColor: Theme.of(context).colorScheme.primary,
135           appBar: AppBar(
136             backgroundColor: Theme.of(context).colorScheme.surface,
137             automaticallyImplyLeading: true,
138             title: const Text('Settings'),
139             centerTitle: false,
140             leading: IconButton(
141               icon: const Icon(Icons.arrow_back_ios_new),
142               onPressed: () {
143                 Navigator.pop(context);
144               },
145             ),
146             elevation: 0,
147           ),
148           body: Padding(
149             padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 8, right: 8),
150             child: SingleChildScrollView(
151               padding: const EdgeInsets.symmetric(horizontal: 16.0),
152               child: Column(
153                 children: [
154                   const SizedBox(height: 32.0),
155                   ...getRecordingSettings((String? newValue) {
156                     if (newValue == null) return;
157                     if (newValue == _selectedLanguage) return;
158                     if (newValue != 'en') {
159                       showDialog(
160                         context: context,
161                         barrierDismissible: false,
162                         builder: (c) => getDialog(
163                           context,
164                           () => Navigator.of(context).pop(),
165                           () => {},
166                           'Language Limitations',
167                           'Speech profiles are only available for English language. We are working on adding support for other languages.',
168                           singleButton: true,
169                         ),
170                       );
171                     }
172                     setState(() => _selectedLanguage = newValue);
173                     SharedPreferencesUtil().recordingsLanguage = _selectedLanguage;
174                     MixpanelManager().recordingLanguageChanged(_selectedLanguage);
175                   }, _selectedLanguage),
176                   ...getPreferencesWidgets(
177                       onOptInAnalytics: () {
178                         setState(() {
179                           optInAnalytics = !SharedPreferencesUtil().optInAnalytics;
180                           SharedPreferencesUtil().optInAnalytics = !SharedPreferencesUtil().optInAnalytics;
181                           optInAnalytics ? MixpanelManager().optInTracking() : MixpanelManager().optOutTracking();
182                         });
183                       },
184                       onOptInEmotionalFeedback: () {
185                         var enabled = !SharedPreferencesUtil().optInEmotionalFeedback;
186                         SharedPreferencesUtil().optInEmotionalFeedback = enabled;
187 
188                         setState(() {
189                           optInEmotionalFeedback = enabled;
190                         });
191 
192                         // Show a mockup notifications to help user understand about Omi Feedback
193                         if (enabled) {
194                           _showMockupOmiFeebackNotification();
195                         }
196                       },
197                       viewPrivacyDetails: () {
198                         Navigator.of(context).push(MaterialPageRoute(builder: (c) => const PrivacyInfoPage()));
199                         MixpanelManager().privacyDetailsPageOpened();
200                       },
201                       optInEmotionalFeedback: optInEmotionalFeedback,
202                       optInAnalytics: optInAnalytics,
203                       devModeEnabled: devModeEnabled,
204                       onDevModeClicked: () {
205                         setState(() {
206                           if (devModeEnabled) {
207                             devModeEnabled = false;
208                             SharedPreferencesUtil().devModeEnabled = false;
209                             MixpanelManager().developerModeDisabled();
210                           } else {
211                             devModeEnabled = true;
212                             MixpanelManager().developerModeEnabled();
213                             SharedPreferencesUtil().devModeEnabled = true;
214                           }
215                         });
216                       },
217                       authorizeSavingRecordings: SharedPreferencesUtil().permissionStoreRecordingsEnabled,
218                       onAuthorizeSavingRecordingsClicked: () async {
219                         await routeToPage(context, const RecordingsStoragePermission());
220                         setState(() {});
221                       }),
222                   const SizedBox(height: 16),
223                   ListTile(
224                     title: const Text('Need help?', style: TextStyle(color: Colors.white)),
225                     subtitle: const Text('team@basedhardware.com'),
226                     contentPadding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
227                     trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
228                     onTap: () {
229                       launchUrl(Uri.parse('mailto:team@basedhardware.com'));
230                       MixpanelManager().supportContacted();
231                     },
232                   ),
233                   ListTile(
234                     contentPadding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
235                     title: const Text('Join the community!', style: TextStyle(color: Colors.white)),
236                     subtitle: const Text('2300+ members and counting.'),
237                     trailing: const Icon(Icons.discord, color: Colors.purple, size: 20),
238                     onTap: () {
239                       launchUrl(Uri.parse('https://discord.gg/ZutWMTJnwA'));
240                       MixpanelManager().joinDiscordClicked();
241                     },
242                   ),
243                   const SizedBox(height: 32.0),
244                   const Align(
245                     alignment: Alignment.centerLeft,
246                     child: Text(
247                       'ADD ONS',
248                       style: TextStyle(
249                         color: Colors.white,
250                       ),
251                       textAlign: TextAlign.start,
252                     ),
253                   ),
254                   getItemAddOn('Plugins', () {
255                     MixpanelManager().pluginsOpened();
256                     routeToPage(context, const PluginsPage());
257                   }, icon: Icons.integration_instructions),
258                   getItemAddOn('Calendar Integration', () {
259                     routeToPage(context, const CalendarPage());
260                   }, icon: Icons.calendar_month),
261                   Divider(
262                     color: Colors.transparent,
263                   ),
264                   getItemAddOn('Speech Recognition', () {
265                     routeToPage(context, const SpeakerIdPage());
266                   }, icon: Icons.multitrack_audio),
267                   getItemAddOn('Identifying Others', () {
268                     routeToPage(context, const UserPeoplePage());
269                   }, icon: Icons.people),
270                   const Divider(
271                     color: Colors.transparent,
272                   ),
273                   getItemAddOn('Developer Mode', () async {
274                     MixpanelManager().devModePageOpened();
275                     await routeToPage(context, const DeveloperSettingsPage());
276                     setState(() {});
277                   }, icon: Icons.code, visibility: devModeEnabled),
278                   const SizedBox(height: 32.0),
279                   const Align(
280                     alignment: Alignment.centerLeft,
281                     child: Text(
282                       'ABOUT US',
283                       style: TextStyle(
284                         color: Colors.white,
285                       ),
286                       textAlign: TextAlign.start,
287                     ),
288                   ),
289                   getItemAddOn('Privacy Policy', () {
290                     Navigator.of(context).push(
291                       MaterialPageRoute(
292                         builder: (c) => const PageWebView(
293                           url: 'https://www.omi.me/pages/privacy',
294                           title: 'Privacy Policy',
295                         ),
296                       ),
297                     );
298                   }, icon: Icons.privacy_tip_outlined, visibility: true),
299                   getItemAddOn('Our Website', () {
300                     Navigator.of(context).push(
301                       MaterialPageRoute(
302                         builder: (c) => const PageWebView(
303                           url: 'https://www.omi.me/',
304                           title: 'omi',
305                         ),
306                       ),
307                     );
308                   }, icon: Icons.language_outlined, visibility: true),
309                   getItemAddOn('About omi', () {
310                     Navigator.of(context).push(
311                       MaterialPageRoute(
312                         builder: (c) => const PageWebView(
313                           url: 'https://www.omi.me/pages/about',
314                           title: 'About Us',
315                         ),
316                       ),
317                     );
318                   }, icon: Icons.people, visibility: true),
319                   const SizedBox(height: 32),
320                   Padding(
321                     padding: const EdgeInsets.all(8),
322                     child: GestureDetector(
323                       onTap: () {
324                         Clipboard.setData(ClipboardData(text: SharedPreferencesUtil().uid));
325                         ScaffoldMessenger.of(context)
326                             .showSnackBar(const SnackBar(content: Text('UID copied to clipboard')));
327                       },
328                       child: Text(
329                         SharedPreferencesUtil().uid,
330                         style: const TextStyle(color: Color.fromARGB(255, 150, 150, 150), fontSize: 16),
331                         maxLines: 1,
332                         textAlign: TextAlign.center,
333                       ),
334                     ),
335                   ),
336                   Padding(
337                     padding: const EdgeInsets.symmetric(horizontal: 8.0),
338                     child: Align(
339                       alignment: Alignment.center,
340                       child: Text(
341                         'Version: $version+$buildVersion',
342                         style: const TextStyle(color: Color.fromARGB(255, 150, 150, 150), fontSize: 16),
343                       ),
344                     ),
345                   ),
346                   const SizedBox(height: 32),
347                 ],
348               ),
349             ),
350           ),
351         ));
352   }
353 }
354 
355 class _MockNotification extends StatelessWidget {
356   const _MockNotification({super.key, required this.path});
357 
358   final String path;
359 
360   @override
361   Widget build(BuildContext context) {
362     // Forgive me, should be a goog dynamic layout but not static image, btw I have no time.
363     return Image.asset(
364       path,
365       fit: BoxFit.fitWidth,
366     );
367   }
368 }
369 
