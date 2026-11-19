import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import 'menu_models.dart';

final menuApiProvider = Provider<MenuApi>((ref) => MenuApi(ref.watch(dioProvider)));

/// Llamadas al backend del menú. Todos los errores salen como [ApiException].
class MenuApi {
  MenuApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<AdminMenu> fetchAdmin() => _call(() async {
        final response = await _dio.get<Json>('/menu/admin');
        return AdminMenu.fromJson(response.data!);
      });

  // Categorías
  Future<void> createCategory(Json data) => _call(() => _dio.post('/menu/categories', data: data));
  Future<void> updateCategory(String id, Json data) => _call(() => _dio.patch('/menu/categories/$id', data: data));
  Future<void> deleteCategory(String id) => _call(() => _dio.delete('/menu/categories/$id'));
  Future<void> reorderCategories(List<String> ids) =>
      _call(() => _dio.put('/menu/categories/order', data: {'ids': ids}));

  // Productos
  Future<String> createProduct(Json data) => _call(() async {
        final response = await _dio.post<Json>('/menu/products', data: data);
        return response.data!['id'] as String;
      });
  Future<void> updateProduct(String id, Json data) => _call(() => _dio.patch('/menu/products/$id', data: data));
  Future<void> deleteProduct(String id) => _call(() => _dio.delete('/menu/products/$id'));
  Future<void> setProductAvailability(String id, bool isAvailable) =>
      _call(() => _dio.patch('/menu/products/$id/availability', data: {'isAvailable': isAvailable}));
  Future<void> removeProductImage(String id) => _call(() => _dio.delete('/menu/products/$id/image'));
  Future<void> uploadProductImage(String id, Uint8List bytes, String filename) => _call(() {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(_mimeFor(filename))),
        });
        return _dio.post('/menu/products/$id/image', data: form);
      });

  // Modificadores
  Future<void> createModifierGroup(Json data) => _call(() => _dio.post('/menu/modifier-groups', data: data));
  Future<void> updateModifierGroup(String id, Json data) =>
      _call(() => _dio.patch('/menu/modifier-groups/$id', data: data));
  Future<void> deleteModifierGroup(String id) => _call(() => _dio.delete('/menu/modifier-groups/$id'));
  Future<void> addModifierOption(String groupId, Json data) =>
      _call(() => _dio.post('/menu/modifier-groups/$groupId/options', data: data));
  Future<void> updateModifierOption(String id, Json data) =>
      _call(() => _dio.patch('/menu/modifier-options/$id', data: data));
  Future<void> deleteModifierOption(String id) => _call(() => _dio.delete('/menu/modifier-options/$id'));
  Future<void> setOptionAvailability(String id, bool isAvailable) =>
      _call(() => _dio.patch('/menu/modifier-options/$id/availability', data: {'isAvailable': isAvailable}));

  // Estaciones e impuestos
  Future<void> createStation(Json data) => _call(() => _dio.post('/menu/stations', data: data));
  Future<void> updateStation(String id, Json data) => _call(() => _dio.patch('/menu/stations/$id', data: data));
  Future<void> deleteStation(String id) => _call(() => _dio.delete('/menu/stations/$id'));
  Future<void> createTaxRate(Json data) => _call(() => _dio.post('/menu/tax-rates', data: data));
  Future<void> updateTaxRate(String id, Json data) => _call(() => _dio.patch('/menu/tax-rates/$id', data: data));
  Future<void> deleteTaxRate(String id) => _call(() => _dio.delete('/menu/tax-rates/$id'));

  static String _mimeFor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'avif' => 'image/avif',
      _ => 'image/jpeg',
    };
  }
}
