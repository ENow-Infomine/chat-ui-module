class XmppConfig {
  static final XmppConfig _instance = XmppConfig._internal();
  factory XmppConfig() => _instance;
  XmppConfig._internal();

  // 1. Define Defaults here. These are effective immediately if init() is never called.
  String wsUrl = "wss://srv1138210.hstgr.cloud/ws";
  String domain = "srv1138210.hstgr.cloud";
  String restApiUrl = "https://srv1138210.hstgr.cloud/api/chat"; 

  // 2. Make parameters optional (nullable)
  void init({
    String? openfireWebSocketUrl, 
    String? openfireDomain,
    String? backendRestUrl
  }) {
    // 3. Only override the default if the client actually provided a new value
    if (openfireWebSocketUrl != null) {
      wsUrl = openfireWebSocketUrl;
    }
    
    if (openfireDomain != null) {
      domain = openfireDomain;
    }
    
    if (backendRestUrl != null) {
      restApiUrl = backendRestUrl;
    }
  }
}