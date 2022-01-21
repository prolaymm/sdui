import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dialog.dart';
import 'http.dart';
import 'logger.dart';
import 'parser.dart';
import 'route.dart';

typedef ActionCallback = Future<String?> Function(BuildContext context);

/// Descriptor of a widget behavior.
/// This class can be used to:
/// - Handle the screen navigation
/// - Handle the page navigation
/// - Execute commands
///
/// ### JSON Attributes
/// - **type**: Type of action. The supported values are:
///   - `Route`: To redirect to another route
///   - `Page`: To redirect to another page, in the context of [PageView]
///   - `Command`: To execute a command on the server
///   - `Share`: Share content
///   - `Navigate`: To navigate users to URLs
/// - **url**: Action URL. This URL represent either the route or a command to execute
///   - `route:/..`: redirect users to previous route
///   - `route:/~`: redirect users to 1st route
///   - URL starting with `route:/<ROUTE_NAME>` redirect user the a named route. (Ex: ``route:/checkout``)
///   - URL starting with `http://` or `https` redirect user to a server driven page
///   - `page:/<PAGE_NUMBER>`: redirect users to a given page. `<PAGE_NUMBER>` is the page index (starting with `0`).
/// - **replacement**: For `type=route`, this indicate if we replace the current view or navigate.
/// - **parameters**: Parameters to add to the URL where to redirect to
/// - **message**: Message to share
class SDUIAction {
  static final Logger _logger = LoggerFactory.create('SDUIAction');
  static final Future<String?> _emptyFuture = Future(() => null);

  String? type;
  String url = '';
  String? message;
  bool replacement = false;
  SDUIDialog? prompt;
  Map<String, dynamic>? parameters;
  bool inDialog = false;

  /// controller associated with the action
  PageController? pageController;

  SDUIAction fromJson(Map<String, dynamic>? attributes) {
    url = attributes?["url"] ?? '';
    type = attributes?["type"];
    message = attributes?['message'];
    replacement = attributes?["replacement"] ?? false;

    var prompt = attributes?["prompt"];
    if (prompt is Map<String, dynamic>) {
      var tmp = SDUIParser.getInstance().fromJson(prompt);
      if (tmp is SDUIDialog) {
        this.prompt = tmp;
      }
    }

    var parameters = attributes?["parameters"];
    if (parameters is Map<String, dynamic>) {
      this.parameters = parameters;
    }
    return this;
  }

  Future<String?> execute(
          BuildContext context, Map<String, dynamic>? data) async =>
      _prompt(context).then((value) => _execute(value, context, data));

  Future<String?> handleResult(BuildContext context, String? result) async {
    if (result == null) {
      return Future.value(null);
    }

    var json = jsonDecode(result);
    if (json is Map<String, dynamic>) {
      var action = SDUIAction().fromJson(json);
      action.pageController = pageController;
      return action
          .execute(context, json)
          .then((value) => handleResult(context, value));
    }
    return Future.value(null);
  }

  Future<String?> _execute(
      String? result, BuildContext context, Map<String, dynamic>? data) async {
    if (result == null) {
      return _emptyFuture;
    }

    // Close the popup
    if (inDialog) {
      Navigator.of(context).pop();
    }

    // Execute the action
    switch (type?.toLowerCase()) {
      case 'route':
        return _gotoRoute(context, data);

      case 'page':
        return _gotoPage(context);

      case 'command':
        return _executeCommand(context, data);

      case 'share':
        return _share(context);

      case 'navigate':
        return _navigate(context);

      default:
        return _emptyFuture;
    }
  }

  Future<String?> _navigate(BuildContext context) async {
    _logger.i('Navigate to $url');
    if (await canLaunch(url)) {
      await launch(url);
      return "ok";
    } else {
      return "";
    }
  }

  Future<String?> _share(BuildContext context) async {
    await Share.share(message ?? '');
    Future.value(null);
  }

  Future<String?> _prompt(BuildContext context) {
    if (prompt == null) {
      return Future.value("ok");
    }

    return showDialog(
        context: context, builder: (context) => prompt!.toWidget(context));
  }

  Future<String?> _gotoPage(BuildContext context) {
    _logger.i('Goto page $url');
    int page = -1;
    try {
      page = int.parse(url.substring(6));
    } catch (e) {
      page = 0;
    }

    pageController?.animateToPage(page,
        duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    return _emptyFuture;
  }

  Future<String?> _gotoRoute(BuildContext context, Map<String, dynamic>? data) {
    _logger.i('Goto route $url');
    if (_isRoute()) {
      var route = url.substring(6);
      if (route == '/..') {
        Navigator.pop(context);
      } else if (route == '/~') {
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        if (replacement) {
          Navigator.pushReplacementNamed(context, route, arguments: parameters);
        } else {
          Navigator.pushNamed(context, route, arguments: parameters);
        }
      }
    } else if (_isNetwork()) {
      if (replacement) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => DynamicRoute(
                  provider: HttpRouteContentProvider(_urlWithParameters()))),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => DynamicRoute(
                  provider: HttpRouteContentProvider(_urlWithParameters()))),
        );
      }
    }
    return _emptyFuture;
  }

  Future<String> _executeCommand(
      BuildContext context, Map<String, dynamic>? data) async {
    _logger.i('Execute command $url');
    return await Http.getInstance().post(_urlWithParameters(), data);
  }

  bool _isRoute() => url.startsWith('route:') == true;

  bool _isNetwork() => url.startsWith('http://') || url.startsWith('https://');

  String _urlWithParameters() {
    String result = url;
    if (parameters != null) {
      String query = '';
      var keys = parameters!.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        String key = keys[i];
        String? value = parameters?[key]?.toString();
        if (value != null) {
          query += '$key=' + Uri.encodeComponent(value) + '&';
        }
      }
      result = query.isEmpty ? url : '$url?$query';
    }
    return result;
  }
}
