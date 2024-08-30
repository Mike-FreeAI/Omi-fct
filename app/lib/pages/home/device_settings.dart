1 import 'dart:ui';
2 
3 import 'package:flutter/material.dart';
4 import 'package:friend_private/backend/preferences.dart';
5 import 'package:friend_private/backend/schema/bt_device.dart';
6 import 'package:friend_private/pages/home/firmware_update.dart';
7 import 'package:friend_private/providers/device_provider.dart';
8 import 'package:friend_private/providers/onboarding_provider.dart';
9 import 'package:friend_private/utils/analytics/mixpanel.dart';
10 import 'package:friend_private/utils/ble/connect.dart';
11 import 'package:gradient_borders/gradient_borders.dart';
12 import 'package:provider/provider.dart';
13 
14 import 'support.dart';
15 
16 class DeviceSettings extends StatelessWidget {
17   final DeviceInfo? deviceInfo;
18   final BTDeviceStruct? device;
19   final bool isDeviceConnected;
20   final bool isNonWearable; // New boolean variable
21 
22   const DeviceSettings({super.key, this.deviceInfo, this.device, this.isDeviceConnected = false, this.isNonWearable = false});
23 
24   @override
25   Widget build(BuildContext context) {
26     return Scaffold(
27       backgroundColor: Theme.of(context).colorScheme.primary,
28       appBar: AppBar(
29         title: const Text('Device Settings'),
30         backgroundColor: Theme.of(context).colorScheme.primary,
31       ),
32       body: Padding(
33         padding: const EdgeInsets.all(4.0),
34         child: ListView(
35           children: [
36             Stack(
37               children: [
38                 Column(
39                   children: deviceSettingsWidgets(deviceInfo, device, context, isNonWearable),
40                 ),
41                 if (!isDeviceConnected)
42                   ClipRRect(
43                     child: BackdropFilter(
44                       filter: ImageFilter.blur(
45                         sigmaX: 3.0,
46                         sigmaY: 3.0,
47                       ),
48                       child: Container(
49                           height: 410,
50                           width: double.infinity,
51                           margin: const EdgeInsets.only(top: 10),
52                           decoration: BoxDecoration(
53                             boxShadow: [
54                               BoxShadow(
55                                 color: Colors.black.withOpacity(0.1),
56                                 spreadRadius: 5,
57                                 blurRadius: 7,
58                                 offset: const Offset(0, 3),
59                               ),
60                             ],
61                           ),
62                           child: const Center(
63                             child: Text(
64                               'Connect your device to access these settings',
65                               style: TextStyle(
66                                 color: Colors.white,
67                                 fontSize: 16,
68                                 fontWeight: FontWeight.w500,
69                               ),
70                             ),
71                           )),
72                     ),
73                   ),
74               ],
75             ),
76             GestureDetector(
77               onTap: () {
78                 Navigator.push(
79                   context,
80                   MaterialPageRoute(
81                     builder: (context) => const SupportPage(),
82                   ),
83                 );
84               },
85               child: const ListTile(
86                 title: Text('Guides & Support'),
87                 trailing: Icon(Icons.arrow_forward_ios),
88               ),
89             ),
90           ],
91         ),
92       ),
93       bottomNavigationBar: isDeviceConnected
94           ? Padding(
95               padding: const EdgeInsets.only(bottom: 70, left: 30, right: 30),
96               child: Container(
97                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
98                 decoration: BoxDecoration(
99                   border: const GradientBoxBorder(
100                     gradient: LinearGradient(colors: [
101                       Color.fromARGB(127, 208, 208, 208),
102                       Color.fromARGB(127, 188, 99, 121),
103                       Color.fromARGB(127, 86, 101, 182),
104                       Color.fromARGB(127, 126, 190, 236)
105                     ]),
106                     width: 2,
107                   ),
108                   borderRadius: BorderRadius.circular(12),
109                 ),
110                 child: TextButton(
111                   onPressed: () {
112                     if (device != null) bleDisconnectDevice(device!);
113                     SharedPreferencesUtil().btDeviceStruct = BTDeviceStruct(id: '', name: '');
114                     SharedPreferencesUtil().deviceName = '';
115                     context.read<DeviceProvider>().setIsConnected(false);
116                     context.read<DeviceProvider>().setConnectedDevice(null);
117                     context.read<DeviceProvider>().updateConnectingStatus(false);
118                     context.read<OnboardingProvider>().stopFindDeviceTimer();
119                     Navigator.of(context).pop();
120                     Navigator.of(context).pop();
121                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
122                       content: Text('Your Friend is ${device == null ? "unpaired" : "disconnected"}  😔'),
123                     ));
124                     MixpanelManager().disconnectFriendClicked();
125                   },
126                   child: Text(
127                     device == null ? "Unpair" : "Disconnect",
128                     style: const TextStyle(color: Colors.white, fontSize: 16),
129                   ),
130                 ),
131               ),
132             )
133           : const SizedBox(),
134     );
135   }
136 }
137 
138 List<Widget> deviceSettingsWidgets(DeviceInfo? deviceInfo, BTDeviceStruct? device, BuildContext context, bool isNonWearable) {
139   return [
140     ListTile(
141       title: const Text('Device Name'),
142       subtitle: Text(device?.name ?? 'Friend'),
143     ),
144     ListTile(
145       title: const Text('Device ID'),
146       subtitle: Text(device?.id ?? '12AB34CD:56EF78GH'),
147     ),
148     GestureDetector(
149       onTap: () {
150         Navigator.push(
151           context,
152           MaterialPageRoute(
153             builder: (context) => FirmwareUpdate(
154               deviceInfo: deviceInfo!,
155               device: device,
156             ),
157           ),
158         );
159       },
160       child: ListTile(
161         title: const Text('Firmware Update'),
162         subtitle: Text(deviceInfo?.firmwareRevision ?? '1.0.2'),
163         trailing: const Icon(Icons.arrow_forward_ios),
164       ),
165     ),
166     ListTile(
167       title: const Text('Hardware Revision'),
168       subtitle: Text(deviceInfo?.hardwareRevision ?? 'XIAO'),
169     ),
170     ListTile(
171       title: const Text('Model Number'),
172       subtitle: Text(deviceInfo?.modelNumber ?? 'Friend'),
173     ),
174     ListTile(
175       title: const Text('Manufacturer Name'),
176       subtitle: Text(deviceInfo?.manufacturerName ?? 'Based Hardware'),
177     ),
178     if (isNonWearable)
179       const ListTile(
180         title: Text('Non-Wearable Device'),
181         subtitle: Text('This device is not wearable.'),
182       ),
183   ];
184 }
185 
