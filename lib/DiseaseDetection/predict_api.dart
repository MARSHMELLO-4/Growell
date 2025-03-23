import 'dart:convert';
import 'package:http/http.dart' as http;
Future<Map<String, dynamic>?> predict(String? Base64Img) async {
  var headers = {
    'Api-Key': '0cuJPkWZ0r0xudTuFRByXCHN0JVS6KTHG1LL4NP1MMcKQg3UZl',
    'Content-Type': 'application/json',
  };

  var request = http.Request('POST', Uri.parse('https://crop.kindwise.com/api/v1/identification'));
  request.headers.addAll(headers);
  request.body = json.encode({
    "images": [
      "data:image/jpeg;base64, $Base64Img"  // Injecting Base64 image string here
    ],
    "similar_images": true,
  });

  http.StreamedResponse response = await request.send();

  // Read response body
  String responseBody = await response.stream.bytesToString();
  print("Response Status Code: ${response.statusCode}");
  print("Response Body: $responseBody");

  if (response.statusCode == 200 || response.statusCode == 201) {
    try {
      return json.decode(responseBody); // Parse JSON if valid
    } catch (e) {
      print("JSON Parsing Error: $e");
      return null;
    }
  } else {
    print("Error: ${response.reasonPhrase}");
    return null;
  }
}

