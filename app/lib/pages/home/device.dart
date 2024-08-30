1 import 'package:flutter/material.dart';
2 import 'package:friend_private/backend/preferences.dart';
3 import 'package:friend_private/backend/schema/bt_device.dart';
4 import 'package:friend_private/providers/device_provider.dart';
5 import 'package:friend_private/utils/analytics/mixpanel.dart';
6 import 'package:friend_private/utils/ble/connect.dart';
7 import 'package:friend_private/widgets/device_widget.dart';
8 import 'package:gradient_borders/box_borders/gradient_box_border.dart';
9 import 'package:provider/provider.dart';
10 
11 import 'device_settings.dart';
12 
13 class ConnectedDevice extends StatefulWidget {
14   final BTDeviceStruct? device;
15   final int batteryLevel;
16   final bool isNonWearable;
17 
18   const ConnectedDevice({super.key, required this.device, required this.batteryLevel, required this.isNonWearable});
19 
20   @override
21   State<ConnectedDevice> createState() => _ConnectedDeviceState();
22 }
23 
24 class _ConnectedDeviceState extends State<ConnectedDevice> {
25   @override
26   Widget build(BuildContext context) {
27     var deviceName = widget.device?.name ?? SharedPreferencesUtil().deviceName;
28     var deviceConnected = widget.device != null;
29 
30     return FutureBuilder<DeviceInfo>(
31       future: DeviceInfo.getDeviceInfo(widget.device),
32       builder: (BuildContext context, AsyncSnapshot<DeviceInfo> snapshot) {
33         return Scaffold(
34           backgroundColor: Theme.of(context).colorScheme.primary,
35           appBar: AppBar(
36             title: Text(deviceConnected ? 'Connected Device' : 'Paired Device'),
37             backgroundColor: Theme.of(context).colorScheme.primary,
38             actions: [
39               IconButton(
40                 onPressed: () {
41                   Navigator.of(context).push(
42                     MaterialPageRoute(
43                       builder: (context) => DeviceSettings(
44                         device: widget.device,
45                         deviceInfo: snapshot.data,
46                         isDeviceConnected: deviceConnected,
47                         isNonWearable: widget.isNonWearable,
48                       ),
49                     ),
50                   );
51                 },
52                 icon: const Icon(Icons.settings),
53               )
54             ],
55           ),
56           body: Column(
57             children: [
58               const SizedBox(height: 32),
59               const DeviceAnimationWidget(),
60               Column(
61                 crossAxisAlignment: CrossAxisAlignment.center,
62                 mainAxisAlignment: MainAxisAlignment.start,
63                 children: [
64                   Text(
65                     '$deviceName (${widget.device?.getShortId() ?? SharedPreferencesUtil().btDeviceStruct.getShortId()})',
66                     style: const TextStyle(
67                       color: Colors.white,
68                       fontSize: 16.0,
69                       fontWeight: FontWeight.w500,
70                       height: 1.5,
71                     ),
72                     textAlign: TextAlign.center,
73                   ),
74                   const SizedBox(height: 12),
75                   if (snapshot.hasData)
76                     Column(
77                       children: [
78                         Text(
79                           '${snapshot.data?.modelNumber}, firmware ${snapshot.data?.firmwareRevision}',
80                           style: const TextStyle(
81                             color: Colors.white,
82                             fontSize: 10.0,
83                             fontWeight: FontWeight.w500,
84                             height: 1,
85                           ),
86                           textAlign: TextAlign.center,
87                         ),
88                         const SizedBox(height: 12),
89                         Text(
90                           'by ${snapshot.data?.manufacturerName}',
91                           style: const TextStyle(
92                             color: Colors.white,
93                             fontSize: 10.0,
94                             fontWeight: FontWeight.w500,
95                             height: 1,
96                           ),
97                           textAlign: TextAlign.center,
98                         ),
99                         const SizedBox(height: 12),
100                       ],
101                     ),
102                   widget.device != null
103                       ? Container(
104                           decoration: BoxDecoration(
105                             color: Colors.transparent,
106                             borderRadius: BorderRadius.circular(10),
107                           ),
108                           child: Row(
109                             mainAxisSize: MainAxisSize.min,
110                             children: [
111                               Container(
112                                 width: 10,
113                                 height: 10,
114                                 decoration: BoxDecoration(
115                                   color: widget.batteryLevel > 75
116                                       ? const Color.fromARGB(255, 0, 255, 8)
117                                       : widget.batteryLevel > 20
118                                           ? Colors.yellow.shade700
119                                           : Colors.red,
120                                   shape: BoxShape.circle,
121                                 ),
122                               ),
123                               const SizedBox(width: 8.0),
124                               Text(
125                                 '${widget.batteryLevel.toString()}% Battery',
126                                 style: const TextStyle(
127                                   color: Colors.white,
128                                   fontSize: 14,
129                                   fontWeight: FontWeight.w600,
130                                 ),
131                               ),
132                             ],
133                           ))
134                       : const SizedBox.shrink(),
135                   if (widget.isNonWearable)
136                     const Padding(
137                       padding: EdgeInsets.only(top: 16.0),
138                       child: Text(
139                         'This is a non-wearable device.',
140                         style: TextStyle(
141                           color: Colors.red,
142                           fontSize: 14,
143                           fontWeight: FontWeight.w600,
144                         ),
145                       ),
146                     ),
147                 ],
148               ),
149               const SizedBox(height: 32),
150               Container(
151                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
152                 decoration: BoxDecoration(
153                   border: const GradientBoxBorder(
154                     gradient: LinearGradient(colors: [
155                       Color.fromARGB(127, 208, 208, 208),
156                       Color.fromARGB(127, 188, 99, 121),
157                       Color.fromARGB(127, 86, 101, 182),
158                       Color.fromARGB(127, 126, 190, 236)
159                     ]),
160                     width: 2,
161                   ),
162                   borderRadius: BorderRadius.circular(12),
163                 ),
164                 child: TextButton(
165                   onPressed: () async {
166                     if (widget.device != null) {
167                       await bleDisconnectDevice(widget.device!);
168                     }
169                     context.read<DeviceProvider>().setIsConnected(false);
170                     context.read<DeviceProvider>().setConnectedDevice(null);
171                     context.read<DeviceProvider>().updateConnectingStatus(false);
172                     Navigator.of(context).pop();
173                     SharedPreferencesUtil().btDeviceStruct = BTDeviceStruct(id: '', name: '');
174                     SharedPreferencesUtil().deviceName = '';
175                     MixpanelManager().disconnectFriendClicked();
176                   },
177                   child: Text(
178                     widget.device == null ? "Unpair" : "Disconnect",
179                     style: const TextStyle(color: Colors.white, fontSize: 16),
180                   ),
181                 ),
182               ),
183             ],
184           ),
185         );
186       },
187     );
188   }
189 }
190 
