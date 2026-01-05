import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:js' as js; 
import 'xmpp_service.dart';
import 'backend_service.dart'; 

class ChatOverlay extends StatefulWidget {
  final String currentUser;
  final String currentPass;
  final Widget child; 

  const ChatOverlay({
    Key? key,
    required this.currentUser,
    required this.currentPass,
    required this.child,
  }) : super(key: key);

  @override
  _ChatOverlayState createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  // --- XMPP Service ---
  late XmppService _xmpp;
  
  // --- UI State ---
  bool _isOpen = false;
  String? _activeChatId; 
  bool _isGroupMode = true;
  bool _isLoadingInbox = true;

  // --- Data State ---
  List<String> _myRooms = [];
  List<String> _myColleagues = [];
  
  // Single Source of Truth for Badges (Key must be Lowercase)
  final Map<String, int> _unreadCounts = {}; 
  
  // Global Badge Count for FAB
  int get _totalGlobalUnread => _unreadCounts.values.fold(0, (sum, count) => sum + count);

  // Chat History & Presence
  final Map<String, List<String>> _history = {};
  final Map<String, Set<String>> _presenceMap = {}; 
  final TextEditingController _ctrl = TextEditingController();

  // --- Helper: Format Timestamp ---
  String _formatTime(DateTime dt) {
    String _twoDigits(int n) => n.toString().padLeft(2, '0');
    // Format: dd/mm/yyyy - hh:mm
    return "${_twoDigits(dt.day)}/${_twoDigits(dt.month)}/${dt.year} - ${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}";
  }

  @override
  void initState() {
    super.initState();
    if (html.Notification.permission != 'granted') html.Notification.requestPermission();
    
    _loadInbox();

    _xmpp = XmppService(
      onConnected: () => print("XMPP Connected"),
      
      // Updated Callback: Accepts timestampStr (nullable)
      onMessage: (from, body, type, timestampStr) {
        
        // FIX 1: Normalize Key to Lowercase (Matches XMPP behavior)
        String chatKey = from.split('@')[0].toLowerCase(); 
        String sender;

        // 1. Handle System Signals
        if (type == 'headline') {
          if (body == 'REFRESH_INBOX') _loadInbox();
          return; // Don't show in chat
        } 
        
        // 2. Determine Sender Name
        if (type == 'groupchat') {
           sender = from.contains('/') ? from.split('/')[1] : "System";
        } else {
           sender = chatKey; 
        }

        // 3. Desktop Notification (Background only)
        if (html.document.visibilityState == 'hidden') {
           if (html.Notification.permission == 'granted') {
              var n = html.Notification("Msg from $sender", body: body);
              n.onClick.listen((e) { 
                js.context.callMethod('focus'); 
                n.close();
                if (mounted) _openChat(chatKey, type == 'groupchat');
              });
           }
        }

        // 4. FIX 2: Handle Timestamp (History vs Live)
        DateTime msgTime;
        if (timestampStr != null && timestampStr.isNotEmpty) {
           // History Message (ISO 8601 from server)
           try {
             msgTime = DateTime.parse(timestampStr).toLocal();
           } catch (e) {
             msgTime = DateTime.now();
           }
        } else {
           // Live Message
           msgTime = DateTime.now();
        }
        String timeString = _formatTime(msgTime);

        // 5. Update State
        if (mounted) {
          setState(() {
            if (!_history.containsKey(chatKey)) _history[chatKey] = [];
            
            // Format: "dd/MM/yyyy - HH:mm - Sender: Body"
            _history[chatKey]!.add("$timeString - $sender: $body");

            // Unread Badge Logic
            // Compare lowercase active ID with lowercase chatKey
            bool isChatVisible = _isOpen && _activeChatId?.toLowerCase() == chatKey;
            
            if (!isChatVisible) {
              _unreadCounts[chatKey] = (_unreadCounts[chatKey] ?? 0) + 1;
            }
          });
        }
      },
    );

    // Presence Stream
    _xmpp.presenceStream.listen((event) {
      if (!mounted) return;
      String from = event['from']!; 
      String status = event['status']!; 
      setState(() {
        if (from.contains('/')) {
          String room = from.split('@')[0].toLowerCase();
          String nick = from.split('/')[1];
          if (!_presenceMap.containsKey(room)) _presenceMap[room] = {};
          if (status == 'offline') _presenceMap[room]!.remove(nick);
          else _presenceMap[room]!.add(nick);
        } else {
          String user = from.split('@')[0].toLowerCase();
          if (!_presenceMap.containsKey(user)) _presenceMap[user] = {};
          if (status == 'offline') _presenceMap[user]!.clear(); 
          else _presenceMap[user]!.add('online');
        }
      });
    });

    _xmpp.connect(widget.currentUser, widget.currentPass);
  }

  Future<void> _loadInbox() async {
    setState(() => _isLoadingInbox = true);
    final data = await BackendService.getInbox(widget.currentUser);
    if (mounted) {
      setState(() {
        _myRooms = data['rooms']!;
        _myColleagues = data['colleagues']!;
        _isLoadingInbox = false;
      });
    }
  }

  void _openChat(String id, bool isGroup) {
    // Normalize ID to lowercase for history/badge lookups
    String normalizedId = id.toLowerCase();
    
    setState(() {
      _isOpen = true;
      _activeChatId = normalizedId; 
      _isGroupMode = isGroup;
      _history[normalizedId] = _history[normalizedId] ?? [];
      
      // Clear badge for this specific chat
      _unreadCounts[normalizedId] = 0;
    });
    
    // Join room (XMPP handles case, but usually lowercase)
    if (isGroup) _xmpp.joinRoom(id, widget.currentUser);
  }

  void _toggleChat() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) _loadInbox();     
    });
  }

  void _send() {
    if (_ctrl.text.isEmpty || _activeChatId == null) return;
    String text = _ctrl.text;
    
    _xmpp.sendMessage(_activeChatId!, text, isGroup: _isGroupMode);
    
    String timeString = _formatTime(DateTime.now());

    setState(() {
      if (!_history.containsKey(_activeChatId!)) _history[_activeChatId!] = [];
      _history[_activeChatId!]!.add("$timeString - Me: $text");
      _ctrl.clear();
    });
  }

  // --- Widget Helpers ---

  Widget _buildBadge(int count) {
    if (count == 0) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      constraints: BoxConstraints(minWidth: 18, minHeight: 18),
      child: Center(
        child: Text(
          count > 9 ? "9+" : "$count",
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildInbox() {
    return Column(
      children: [
        // Inbox Header
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.blue[50],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Chats", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[900])),
              IconButton(
                icon: Icon(Icons.close, size: 22, color: Colors.blue[800]),
                onPressed: _toggleChat, 
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              )
            ],
          ),
        ),
        // Inbox List
        Expanded(
          child: _isLoadingInbox 
            ? Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadInbox,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (_myRooms.isEmpty && _myColleagues.isEmpty)
                      Padding(padding: EdgeInsets.all(20), child: Text("No active chats found.")),

                    if (_myRooms.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text("MY TICKETS", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      ..._myRooms.map((r) {
                        // FIX: Lookup using lowercase key
                        int count = _unreadCounts[r.toLowerCase()] ?? 0;
                        
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.confirmation_number, size: 20, color: Colors.blue),
                          title: Text(r, style: TextStyle(fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal)),
                          
                          // FIX: SizedBox prevents layout error
                          trailing: SizedBox(
                            width: 32.0,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: count > 0 
                                ? _buildBadge(count) 
                                : Icon(Icons.chevron_right, size: 16, color: Colors.grey[300]),
                            ),
                          ),
                          onTap: () => _openChat(r, true),
                        );
                      }).toList(),
                    ],

                    if (_myColleagues.isNotEmpty) ...[
                      Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text("DIRECT MESSAGES", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      ..._myColleagues.map((u) {
                        // FIX: Lookup using lowercase key
                        int count = _unreadCounts[u.toLowerCase()] ?? 0;
                        bool isOnline = (_presenceMap[u.toLowerCase()]?.isNotEmpty ?? false);

                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.person, size: 20, color: Colors.green),
                          title: Text(u, style: TextStyle(fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal)),
                          
                          // FIX: SizedBox prevents layout error
                          trailing: SizedBox(
                            width: 32.0,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: count > 0 
                                ? _buildBadge(count)
                                : Container(
                                    width: 8, height: 8,
                                    decoration: BoxDecoration(
                                      color: isOnline ? Colors.green : Colors.grey[300],
                                      shape: BoxShape.circle
                                    ),
                                  ),
                            ),
                          ),
                          onTap: () => _openChat(u, false),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        // Chat Header
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: Colors.blue[800], 
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () => setState(() {
                  _activeChatId = null; 
                  _loadInbox(); 
                }),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeChatId ?? "Chat",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text("Online", style: TextStyle(color: Colors.white70, fontSize: 10)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: _toggleChat,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
            ],
          ),
        ),
        
        // Chat Messages
        Expanded(
          child: Container(
            color: Colors.grey[100],
            child: ListView.builder(
              padding: EdgeInsets.all(12),
              itemCount: (_history[_activeChatId!] ?? []).length,
              itemBuilder: (ctx, i) {
                String msg = _history[_activeChatId!]![i];
                
                // PARSING LOGIC: "Timestamp - Sender: Body"
                // Finds the ": " separator
                int splitIndex = msg.indexOf(": ");
                String headerInfo; 
                String displayMsg;

                if (splitIndex != -1) {
                  headerInfo = msg.substring(0, splitIndex); 
                  displayMsg = msg.substring(splitIndex + 2).trim(); 
                } else {
                  headerInfo = "Unknown";
                  displayMsg = msg;
                }

                bool isMe = headerInfo.endsWith(" - Me");

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[100] : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                        bottomLeft: isMe ? Radius.circular(12) : Radius.circular(0),
                        bottomRight: isMe ? Radius.circular(0) : Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header (Timestamp - Sender)
                        Text(
                          headerInfo, 
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600])
                        ),
                        SizedBox(height: 2),
                        // Body
                        Text(displayMsg, style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        // Input Area
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          padding: EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: "Type a message...",
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[300]!)),
                    isDense: true,
                    fillColor: Colors.grey[50],
                    filled: true,
                  ),
                ),
              ),
              SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blue[800],
                radius: 18,
                child: IconButton(
                  icon: Icon(Icons.send, color: Colors.white, size: 16),
                  onPressed: _send,
                  padding: EdgeInsets.zero,
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // CHAT WINDOW (Open)
        if (_isOpen)
          Positioned(
            bottom: 20, 
            right: 20,
            child: Material(
              elevation: 10, 
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 320, 
                height: 450,
                child: _activeChatId == null ? _buildInbox() : _buildChat(),
              ),
            ),
          ),

        // FAB ICON (Closed)
        if (!_isOpen)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.blue[800],
              onPressed: _toggleChat,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.chat),
                  
                  // Global Badge
                  if (_totalGlobalUnread > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Center(
                          child: Text(
                            _totalGlobalUnread > 9 ? "9+" : "$_totalGlobalUnread",
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),        
      ],
    );
  }
}