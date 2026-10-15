import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sieuthimini/services/api_contract.dart';
import 'package:sieuthimini/services/session_client.dart';
import 'package:sieuthimini/services/token_store.dart';

void main() {
  test('wire JSON is recursively snake_case and canonical values win', () {
    expect(
      ApiContract.toWire({
        'orderId': 1,
        'order_id': 2,
        'items': [
          {'importPrice': null, 'stockQuantity': 0},
        ],
        'paymentURL': 'https://example.test',
      }),
      {
        'order_id': 2,
        'items': [
          {'import_price': null, 'stock_quantity': 0},
        ],
        'payment_url': 'https://example.test',
      },
    );
  });
  test(
    'legacy domain consumers can read snake_case without a Hive migration',
    () {
      final value = ApiContract.decode(
        '{"discount_amount":12,"items":[{"stock_quantity":0}],"payment_url":"https://example.test"}',
      );
      expect(value['discount_amount'], 12);
      expect(value['discountAmount'], 12);
      expect(value['items'][0]['stockQuantity'], 0);
      expect(value['paymentUrl'], 'https://example.test');
      expect(ApiContract.toWire(value), {
        'discount_amount': 12,
        'items': [
          {'stock_quantity': 0},
        ],
        'payment_url': 'https://example.test',
      });
    },
  );
  test(
    'shared client sends canonical JSON and leaves multipart bytes intact',
    () async {
      final received = <http.Request>[];
      final client = SessionClient(
        baseUrl: () => 'https://api.test',
        tokens: TokenStore(),
        transport: MockClient((request) async {
          received.add(request);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await client.post(
        Uri.parse('https://api.test/api/vouchers/validate'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'orderTotal': 100, 'userId': 1}),
      );
      expect(jsonDecode(received[0].body), {'order_total': 100, 'user_id': 1});
      await client.post(
        Uri.parse('https://api.test/api/uploads/product-image'),
        headers: {'Content-Type': 'multipart/form-data; boundary=abc'},
        body: 'rawImageBytes',
      );
      expect(received[1].body, 'rawImageBytes');
    },
  );
}
