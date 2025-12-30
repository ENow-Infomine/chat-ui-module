class XmppConfig {
  static final XmppConfig _instance = XmppConfig._internal();
  factory XmppConfig() => _instance;
  XmppConfig._internal();

  String wsUrl = "ws://localhost:5280/ws";
  String domain = "localhost";
  String restApiUrl = "http://localhost:8080/api"; // NEW

  void init({
    required String openfireWebSocketUrl, 
    required String openfireDomain,
    required String backendRestUrl // NEW param
  }) {
    wsUrl = openfireWebSocketUrl;
    domain = openfireDomain;
    restApiUrl = backendRestUrl;
  }
}
