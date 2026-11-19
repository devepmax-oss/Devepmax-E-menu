import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gopicadera/core/config/app_config.dart';
import 'package:gopicadera/core/widget/app_network_image.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();

  List<MenuProduct> _products = [];
  List<MenuCategoryView> _loadedCategories = [];
  MenuProduct? _selectedProduct;

  bool _loading = true;
  bool _saving = false;
  bool _savingImage = false;
  bool _hasError = false;
  String _searchQuery = '';
  String _selectedCategory = 'Todas';
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();

    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
      _ensureSelection();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _hasError = false;
        });
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/products'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);

      final List<MenuProduct> loaded = [];
      final List<MenuCategoryView> loadedCategories = [];

      if (decoded is List) {
        // Backend nuevo: /api/products responde una lista de categorías,
        // cada una con su arreglo products. También conservamos el id real
        // de la categoría para poder renombrarla o eliminarla desde la app.
        for (final categoryEntry in decoded) {
          if (categoryEntry is! Map) continue;
          final category = Map<String, dynamic>.from(categoryEntry);
          final categoryId = (category['id'] ?? '').toString();
          final categoryName = (category['name'] ?? 'Sin categoría').toString();
          final rawProducts = category['products'];

          int productCount = 0;
          String categoryImageUrl = '';

          if (rawProducts is List) {
            for (final rawProduct in rawProducts) {
              if (rawProduct is! Map) continue;
              final productJson = Map<String, dynamic>.from(rawProduct);
              productJson['categoryId'] = categoryId;
              productJson['categoryName'] = categoryName;

              if (categoryImageUrl.isEmpty) {
                categoryImageUrl = (productJson['imageUrl'] ?? '').toString();
              }

              loaded.add(MenuProduct.fromJson(productJson));
              productCount++;
            }
          }

          loadedCategories.add(
            MenuCategoryView(
              id: categoryId,
              name: _normalizedCategoryLabel(categoryName),
              imageUrl: categoryImageUrl,
              count: productCount,
            ),
          );
        }
      } else if (decoded is Map<String, dynamic>) {
        // Compatibilidad con respuestas legacy: { products: [...] }
        final rawProducts = decoded['products'];
        if (rawProducts is List) {
          loaded.addAll(
            rawProducts
                .whereType<Map>()
                .map((e) => MenuProduct.fromJson(Map<String, dynamic>.from(e))),
          );
        }
      }

      loaded
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      for (final p in loaded) {
        debugPrint('MENU PRODUCT => id=${p.id} name=${p.name}');
        debugPrint('MENU PRODUCT IMAGE RAW => ${p.imageUrl}');
        debugPrint(
          'MENU PRODUCT IMAGE NORMALIZED => ${normalizeImageUrl(p.imageUrl)}',
        );
      }

      if (!mounted) return;

      setState(() {
        _products = loaded;
        _loadedCategories = loadedCategories;
        _loading = false;
      });

      _ensureValidCategory();
      _ensureSelection();
    } catch (e) {
      debugPrint('Error loading products: $e');

      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  String _normalizedCategoryLabel(String rawCategory) {
    final trimmed = rawCategory.trim();
    if (trimmed.isEmpty) return 'Sin categoría';

    final pieces = trimmed
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (pieces.isEmpty) return 'Sin categoría';
    return pieces.first;
  }

  List<MenuCategoryView> get _categories {
    if (_loadedCategories.isNotEmpty) {
      final categories = _loadedCategories
          .where((category) => category.name.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      return [
        MenuCategoryView(
          id: '',
          name: 'Todas',
          imageUrl: '',
          count: _products.length,
        ),
        ...categories,
      ];
    }

    final map = <String, MenuCategoryView>{};

    for (final product in _products) {
      final categoryLabel = _normalizedCategoryLabel(product.category);

      if (!map.containsKey(categoryLabel)) {
        map[categoryLabel] = MenuCategoryView(
          id: product.categoryId,
          name: categoryLabel,
          imageUrl: product.imageUrl,
          count: 1,
        );
      } else {
        final current = map[categoryLabel]!;
        map[categoryLabel] = MenuCategoryView(
          id: current.id.isNotEmpty ? current.id : product.categoryId,
          name: current.name,
          imageUrl: current.imageUrl.isNotEmpty
              ? current.imageUrl
              : (product.imageUrl.isNotEmpty ? product.imageUrl : ''),
          count: current.count + 1,
        );
      }
    }

    final categories = map.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return [
      MenuCategoryView(
        id: '',
        name: 'Todas',
        imageUrl: '',
        count: _products.length,
      ),
      ...categories,
    ];
  }

  void _ensureValidCategory() {
    final names = _categories.map((e) => e.name).toSet();
    if (!names.contains(_selectedCategory)) {
      if (mounted) {
        setState(() {
          _selectedCategory = 'Todas';
        });
      } else {
        _selectedCategory = 'Todas';
      }
    }
  }

  List<MenuProduct> get _categoryFilteredProducts {
    if (_selectedCategory == 'Todas') return _products;

    return _products.where((product) {
      final category = _normalizedCategoryLabel(product.category);
      return category == _selectedCategory;
    }).toList();
  }

  List<MenuProduct> get _filteredProducts {
    final base = _categoryFilteredProducts;

    if (_searchQuery.isEmpty) return base;

    final q = _searchQuery.toLowerCase();

    return base.where((product) {
      return product.name.toLowerCase().contains(q) ||
          product.description.toLowerCase().contains(q) ||
          product.category.toLowerCase().contains(q) ||
          product.id.toString().contains(q);
    }).toList();
  }

  void _ensureSelection() {
    final visible = _filteredProducts;

    if (visible.isEmpty) {
      if (_selectedProduct != null && mounted) {
        setState(() {
          _selectedProduct = null;
        });
      }
      return;
    }

    final stillVisible = _selectedProduct != null &&
        visible.any((p) => p.id == _selectedProduct!.id);

    if (!stillVisible) {
      _selectProduct(visible.first);
    }
  }

  void _applySelectedProduct(MenuProduct product) {
    _selectedProduct = product;
    _nameController.text = product.name;
    _descriptionController.text = product.description;
    _priceController.text = product.price.toStringAsFixed(2);
    _categoryController.text = _normalizedCategoryLabel(product.category);
    _isVisible = product.isActive;
  }

  void _selectProduct(MenuProduct product) {
    if (!mounted) return;
    setState(() {
      _applySelectedProduct(product);
    });
  }

  void _replaceProductInList(MenuProduct updated) {
    final index = _products.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      _products[index] = updated;
    }
  }

  Future<void> _saveProduct() async {
    final product = _selectedProduct;
    if (product == null) {
      _showSnack('No hay plato seleccionado');
      return;
    }

    final parsedPrice = double.tryParse(_priceController.text.trim());
    if (parsedPrice == null) {
      _showSnack('Precio inválido');
      return;
    }

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final category = _categoryController.text.trim().isEmpty
        ? product.category
        : _categoryController.text.trim();

    if (name.isEmpty) {
      _showSnack('El nombre es requerido');
      return;
    }

    final payload = {
      'name': name,
      'description': description,
      'price': parsedPrice,
      'category': category,
      'isActive': _isVisible,
    };

    try {
      if (mounted) {
        setState(() {
          _saving = true;
        });
      }

      final url = Uri.parse('$baseUrl/api/products/${product.id}');
      debugPrint('PATCH => $url');
      debugPrint('PATCH BODY => ${jsonEncode(payload)}');

      final response = await http.patch(
        url,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
        body: jsonEncode(payload),
      );

      debugPrint('SAVE PRODUCT RESPONSE => ${response.statusCode}');
      debugPrint('SAVE PRODUCT BODY => ${response.body}');

      if (response.statusCode >= 400) {
        throw Exception(
          'No se pudo guardar el plato: ${response.statusCode} ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      final data =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      final productJson = data['product'];
      if (productJson is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al guardar producto');
      }

      final updated = MenuProduct.fromJson(productJson);

      if (!mounted) return;

      setState(() {
        _replaceProductInList(updated);
        _applySelectedProduct(updated);
        _products = List.from(_products);
        _saving = false;
      });

      _ensureValidCategory();
      _ensureSelection();
      _showSnack('Plato guardado');
    } catch (e) {
      debugPrint('Error saving plato: $e');

      if (!mounted) return;
      setState(() {
        _saving = false;
      });

      _showSnack('Error guardando: $e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    final product = _selectedProduct;
    if (product == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;

      if (mounted) {
        setState(() {
          _savingImage = true;
        });
      }

      final request = http.MultipartRequest(
        'PATCH',
        Uri.parse('$baseUrl/api/products/${product.id}/image'),
      );

      request.headers.addAll(const {
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
      });

      if (file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'imageFile',
            file.path!,
            filename: file.name,
          ),
        );
      } else if (file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'imageFile',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else {
        throw Exception('No se pudo leer el archivo seleccionado');
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('UPDATE IMAGE RESPONSE => ${response.statusCode}');
      debugPrint('UPDATE IMAGE BODY => ${response.body}');

      if (response.statusCode >= 400) {
        throw Exception(
          'No se pudo actualizar la imagen: ${response.statusCode} ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      final data =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      final productJson = data['product'];
      if (productJson is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al actualizar imagen');
      }

      final updated = MenuProduct.fromJson(productJson);

      debugPrint('UPDATED PRODUCT IMAGE RAW => ${updated.imageUrl}');
      debugPrint(
        'UPDATED PRODUCT IMAGE NORMALIZED => ${normalizeImageUrl(updated.imageUrl)}',
      );

      if (!mounted) return;

      setState(() {
        _replaceProductInList(updated);
        _applySelectedProduct(updated);
        _products = List.from(_products);
        _savingImage = false;
      });

      _ensureValidCategory();
      _showSnack('Imagen actualizada');
    } catch (e) {
      debugPrint('Error updating image: $e');

      if (!mounted) return;
      setState(() {
        _savingImage = false;
      });

      _showSnack('No se pudo actualizar la imagen');
    }
  }

  Future<void> _toggleStatus(MenuProduct product) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/products/${product.id}'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
        body: jsonEncode({
          'isActive': !product.isActive,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception('No se pudo cambiar visibilidad');
      }

      final decoded = jsonDecode(response.body);
      final data =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

      final productJson = data['product'];
      if (productJson is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al cambiar visibilidad');
      }

      final updated = MenuProduct.fromJson(productJson);

      if (!mounted) return;

      setState(() {
        _replaceProductInList(updated);
        if (_selectedProduct?.id == updated.id) {
          _applySelectedProduct(updated);
        }
        _products = List.from(_products);
      });

      _showSnack(updated.isActive ? 'Plato visible' : 'Plato oculto');
    } catch (e) {
      debugPrint('Error toggling status: $e');
      _showSnack('No se pudo cambiar la visibilidad');
    }
  }

  Future<void> _deleteProduct(MenuProduct product) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Eliminar plato'),
              content: Text(
                '¿Seguro que deseas eliminar "${product.name}"?\n\nSe eliminará de todos los menús.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB42318),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Eliminar'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/products/${product.id}'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      if (response.statusCode >= 400) {
        throw Exception('No se pudo eliminar el plato');
      }

      if (!mounted) return;

      setState(() {
        _products.removeWhere((p) => p.id == product.id);
        if (_selectedProduct?.id == product.id) {
          _selectedProduct = null;
        }
      });

      _ensureValidCategory();
      _ensureSelection();
      _showSnack('Plato eliminado');
    } catch (e) {
      debugPrint('Error deleting plato: $e');
      _showSnack('No se pudo eliminar el plato');
    }
  }

  Future<void> _refreshSelectedProductDetails() async {
    final product = _selectedProduct;
    if (product == null) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/products/${product.id}'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      if (response.statusCode >= 400) {
        throw Exception(
          'No se pudo refrescar el plato: ${response.statusCode} ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Respuesta inválida al refrescar plato');
      }

      final updated = MenuProduct.fromJson(decoded);

      if (!mounted) return;

      setState(() {
        _replaceProductInList(updated);
        _applySelectedProduct(updated);
        _products = List.from(_products);
      });
    } catch (e) {
      debugPrint('Error refreshing product modifiers: $e');
      _showSnack('No se pudo refrescar las opciones del plato');
    }
  }

  Future<void> _createModifierGroup(MenuProduct product) async {
    final nameController = TextEditingController();
    final minController = TextEditingController(text: '0');
    final maxController = TextEditingController(text: '1');

    String selectionType = 'single';
    bool isRequired = false;
    bool submitting = false;
    bool createdSuccessfully = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> submit() async {
              if (submitting) return;

              final name = nameController.text.trim();
              final minSelect = int.tryParse(minController.text.trim()) ?? 0;
              final maxSelect = int.tryParse(maxController.text.trim()) ?? 1;

              if (name.isEmpty) {
                _showSnack('El nombre del grupo es requerido');
                return;
              }

              if (minSelect < 0) {
                _showSnack('El mínimo no puede ser negativo');
                return;
              }

              if (maxSelect < 1) {
                _showSnack('El máximo debe ser al menos 1');
                return;
              }

              if (selectionType == 'single' && maxSelect != 1) {
                _showSnack('La selección única debe tener máximo 1');
                return;
              }

              if (minSelect > maxSelect) {
                _showSnack('El mínimo no puede ser mayor que el máximo');
                return;
              }

              try {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = true;
                  });
                }

                final response = await http.post(
                  Uri.parse('$baseUrl/api/modifiers/groups'),
                  headers: const {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
                  },
                  body: jsonEncode({
                    'productId': product.id,
                    'name': name,
                    'selectionType': selectionType,
                    'minSelect': minSelect,
                    'maxSelect': maxSelect,
                    'isRequired': isRequired,
                  }),
                );

                debugPrint(
                  'CREATE MODIFIER GROUP RESPONSE => ${response.statusCode}',
                );
                debugPrint('CREATE MODIFIER GROUP BODY => ${response.body}');

                if (response.statusCode >= 400) {
                  throw Exception(
                    'No se pudo crear el grupo: ${response.statusCode} ${response.body}',
                  );
                }

                createdSuccessfully = true;

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (e) {
                debugPrint('Error creating modifier group: $e');

                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                  });
                }

                _showSnack('No se pudo crear el grupo');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Nuevo grupo de opciones'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _EditorLabel('Nombre del grupo'),
                      const SizedBox(height: 8),
                      _EditorField(controller: nameController),
                      const SizedBox(height: 12),
                      const _EditorLabel('Tipo de selección'),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'single',
                            label: Text('Única'),
                            icon: Icon(Icons.radio_button_checked_rounded),
                          ),
                          ButtonSegment(
                            value: 'multiple',
                            label: Text('Múltiple'),
                            icon: Icon(Icons.check_box_rounded),
                          ),
                        ],
                        selected: {selectionType},
                        onSelectionChanged: submitting
                            ? null
                            : (values) {
                                final value = values.first;
                                setLocalState(() {
                                  selectionType = value;
                                  if (selectionType == 'single') {
                                    maxController.text = '1';
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _EditorLabel('Mínimo'),
                                const SizedBox(height: 5),
                                _EditorField(
                                  controller: minController,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _EditorLabel('Máximo'),
                                const SizedBox(height: 8),
                                _EditorField(
                                  controller: maxController,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isRequired,
                        onChanged: submitting
                            ? null
                            : (value) {
                                setLocalState(() {
                                  isRequired = value;
                                  if (isRequired &&
                                      minController.text.trim() == '0') {
                                    minController.text = '1';
                                  }
                                });
                              },
                        title: const Text(
                          'Obligatorio',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        subtitle: const Text(
                          'El cliente debe seleccionar una opción de este grupo.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                  ),
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(submitting ? 'Creando...' : 'Crear grupo'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      minController.dispose();
      maxController.dispose();
    });

    if (!createdSuccessfully || !mounted) return;

    await _refreshSelectedProductDetails();

    if (!mounted) return;
    _showSnack('Grupo de opciones creado');
  }

  Future<void> _createModifierOption(MenuModifierGroup group) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: '0.00');

    bool submitting = false;
    bool createdSuccessfully = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> submit() async {
              if (submitting) return;

              final name = nameController.text.trim();
              final priceAdjustment =
                  double.tryParse(priceController.text.trim()) ?? 0;

              if (name.isEmpty) {
                _showSnack('El nombre de la opción es requerido');
                return;
              }

              if (priceAdjustment < 0) {
                _showSnack('El precio extra no puede ser negativo');
                return;
              }

              try {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = true;
                  });
                }

                final response = await http.post(
                  Uri.parse('$baseUrl/api/modifiers/options'),
                  headers: const {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
                  },
                  body: jsonEncode({
                    'modifierGroupId': group.id,
                    'name': name,
                    'priceAdjustment': priceAdjustment,
                  }),
                );

                debugPrint(
                  'CREATE MODIFIER OPTION RESPONSE => ${response.statusCode}',
                );
                debugPrint('CREATE MODIFIER OPTION BODY => ${response.body}');

                if (response.statusCode >= 400) {
                  throw Exception(
                    'No se pudo crear la opción: ${response.statusCode} ${response.body}',
                  );
                }

                createdSuccessfully = true;

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (e) {
                debugPrint('Error creating modifier option: $e');

                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                  });
                }

                _showSnack('No se pudo crear la opción');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text('Nueva opción para ${group.name}'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _EditorLabel('Nombre de la opción'),
                    const SizedBox(height: 8),
                    _EditorField(controller: nameController),
                    const SizedBox(height: 16),
                    const _EditorLabel('Precio extra'),
                    const SizedBox(height: 8),
                    _EditorField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                  ),
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(submitting ? 'Creando...' : 'Crear opción'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      priceController.dispose();
    });

    if (!createdSuccessfully || !mounted) return;

    await _refreshSelectedProductDetails();

    if (!mounted) return;
    _showSnack('Opción creada');
  }

  Future<void> _editModifierGroup(MenuModifierGroup group) async {
    final nameController = TextEditingController(text: group.name);
    final minController =
        TextEditingController(text: group.minSelect.toString());
    final maxController =
        TextEditingController(text: group.maxSelect.toString());

    String selectionType =
        group.selectionType == 'multiple' ? 'multiple' : 'single';
    bool isRequired = group.isRequired;
    bool submitting = false;
    bool updatedSuccessfully = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> submit() async {
              if (submitting) return;

              final name = nameController.text.trim();
              final minSelect = int.tryParse(minController.text.trim()) ?? 0;
              final maxSelect = int.tryParse(maxController.text.trim()) ?? 1;

              if (name.isEmpty) {
                _showSnack('El nombre del grupo es requerido');
                return;
              }

              if (minSelect < 0) {
                _showSnack('El mínimo no puede ser negativo');
                return;
              }

              if (maxSelect < 1) {
                _showSnack('El máximo debe ser al menos 1');
                return;
              }

              if (selectionType == 'single' && maxSelect != 1) {
                _showSnack('La selección única debe tener máximo 1');
                return;
              }

              if (minSelect > maxSelect) {
                _showSnack('El mínimo no puede ser mayor que el máximo');
                return;
              }

              try {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = true;
                  });
                }

                final response = await http.patch(
                  Uri.parse('$baseUrl/api/modifiers/groups/${group.id}'),
                  headers: const {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
                  },
                  body: jsonEncode({
                    'name': name,
                    'selectionType': selectionType,
                    'minSelect': minSelect,
                    'maxSelect': maxSelect,
                    'isRequired': isRequired,
                  }),
                );

                debugPrint(
                  'UPDATE MODIFIER GROUP RESPONSE => ${response.statusCode}',
                );
                debugPrint('UPDATE MODIFIER GROUP BODY => ${response.body}');

                if (response.statusCode >= 400) {
                  throw Exception(
                    'No se pudo actualizar el grupo: ${response.statusCode} ${response.body}',
                  );
                }

                updatedSuccessfully = true;

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (e) {
                debugPrint('Error updating modifier group: $e');

                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                  });
                }

                _showSnack('No se pudo actualizar el grupo');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Editar grupo de opciones'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _EditorLabel('Nombre del grupo'),
                      const SizedBox(height: 8),
                      _EditorField(controller: nameController),
                      const SizedBox(height: 16),
                      const _EditorLabel('Tipo de selección'),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'single',
                            label: Text('Única'),
                            icon: Icon(Icons.radio_button_checked_rounded),
                          ),
                          ButtonSegment(
                            value: 'multiple',
                            label: Text('Múltiple'),
                            icon: Icon(Icons.check_box_rounded),
                          ),
                        ],
                        selected: {selectionType},
                        onSelectionChanged: submitting
                            ? null
                            : (values) {
                                final value = values.first;
                                setLocalState(() {
                                  selectionType = value;
                                  if (selectionType == 'single') {
                                    maxController.text = '1';
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _EditorLabel('Mínimo'),
                                const SizedBox(height: 8),
                                _EditorField(
                                  controller: minController,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _EditorLabel('Máximo'),
                                const SizedBox(height: 8),
                                _EditorField(
                                  controller: maxController,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isRequired,
                        onChanged: submitting
                            ? null
                            : (value) {
                                setLocalState(() {
                                  isRequired = value;
                                  if (isRequired &&
                                      minController.text.trim() == '0') {
                                    minController.text = '1';
                                  }
                                });
                              },
                        title: const Text(
                          'Obligatorio',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        subtitle: const Text(
                          'El cliente debe seleccionar una opción de este grupo.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                  ),
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(submitting ? 'Guardando...' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      minController.dispose();
      maxController.dispose();
    });

    if (!updatedSuccessfully || !mounted) return;

    await _refreshSelectedProductDetails();

    if (!mounted) return;
    _showSnack('Grupo actualizado');
  }

  Future<void> _deleteModifierGroup(MenuModifierGroup group) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Eliminar grupo'),
              content: Text(
                '¿Seguro que deseas eliminar "${group.name}"?\n\nTambién se ocultarán sus opciones.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB42318),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Eliminar'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/modifiers/groups/${group.id}'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      debugPrint('DELETE MODIFIER GROUP RESPONSE => ${response.statusCode}');
      debugPrint('DELETE MODIFIER GROUP BODY => ${response.body}');

      if (response.statusCode >= 400) {
        throw Exception(
          'No se pudo eliminar el grupo: ${response.statusCode} ${response.body}',
        );
      }

      await _refreshSelectedProductDetails();

      if (!mounted) return;
      _showSnack('Grupo eliminado');
    } catch (e) {
      debugPrint('Error deleting modifier group: $e');
      _showSnack('No se pudo eliminar el grupo');
    }
  }

  Future<void> _editModifierOption(
    MenuModifierGroup group,
    MenuModifierOption option,
  ) async {
    final nameController = TextEditingController(text: option.name);
    final priceController = TextEditingController(
      text: option.priceAdjustment.toStringAsFixed(2),
    );

    bool submitting = false;
    bool updatedSuccessfully = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> submit() async {
              if (submitting) return;

              final name = nameController.text.trim();
              final priceAdjustment =
                  double.tryParse(priceController.text.trim()) ?? 0;

              if (name.isEmpty) {
                _showSnack('El nombre de la opción es requerido');
                return;
              }

              if (priceAdjustment < 0) {
                _showSnack('El precio extra no puede ser negativo');
                return;
              }

              try {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = true;
                  });
                }

                final response = await http.patch(
                  Uri.parse('$baseUrl/api/modifiers/options/${option.id}'),
                  headers: const {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
                  },
                  body: jsonEncode({
                    'name': name,
                    'priceAdjustment': priceAdjustment,
                  }),
                );

                debugPrint(
                  'UPDATE MODIFIER OPTION RESPONSE => ${response.statusCode}',
                );
                debugPrint('UPDATE MODIFIER OPTION BODY => ${response.body}');

                if (response.statusCode >= 400) {
                  throw Exception(
                    'No se pudo actualizar la opción: ${response.statusCode} ${response.body}',
                  );
                }

                updatedSuccessfully = true;

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (e) {
                debugPrint('Error updating modifier option: $e');

                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                  });
                }

                _showSnack('No se pudo actualizar la opción');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text('Editar opción de ${group.name}'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _EditorLabel('Nombre de la opción'),
                    const SizedBox(height: 8),
                    _EditorField(controller: nameController),
                    const SizedBox(height: 16),
                    const _EditorLabel('Precio extra'),
                    const SizedBox(height: 8),
                    _EditorField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                  ),
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(submitting ? 'Guardando...' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      priceController.dispose();
    });

    if (!updatedSuccessfully || !mounted) return;

    await _refreshSelectedProductDetails();

    if (!mounted) return;
    _showSnack('Opción actualizada');
  }

  Future<void> _deleteModifierOption(
    MenuModifierGroup group,
    MenuModifierOption option,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Eliminar opción'),
              content: Text(
                '¿Seguro que deseas eliminar "${option.name}" del grupo "${group.name}"?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB42318),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Eliminar'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/modifiers/options/${option.id}'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      debugPrint('DELETE MODIFIER OPTION RESPONSE => ${response.statusCode}');
      debugPrint('DELETE MODIFIER OPTION BODY => ${response.body}');

      if (response.statusCode >= 400) {
        throw Exception(
          'No se pudo eliminar la opción: ${response.statusCode} ${response.body}',
        );
      }

      await _refreshSelectedProductDetails();

      if (!mounted) return;
      _showSnack('Opción eliminada');
    } catch (e) {
      debugPrint('Error deleting modifier option: $e');
      _showSnack('No se pudo eliminar la opción');
    }
  }

  Future<void> _renameCategory(MenuCategoryView category) async {
    if (category.id.isEmpty || category.name == 'Todas') return;

    final nameController = TextEditingController(text: category.name);
    bool submitting = false;
    String? updatedName;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> submit() async {
              if (submitting) return;

              final name = nameController.text.trim();

              if (name.isEmpty) {
                _showSnack('El nombre de la categoría es requerido');
                return;
              }

              try {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = true;
                  });
                }

                final response = await http.patch(
                  Uri.parse('$baseUrl/api/products/categories/${category.id}'),
                  headers: const {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
                  },
                  body: jsonEncode({
                    'name': name,
                  }),
                );

                debugPrint(
                    'UPDATE CATEGORY RESPONSE => ${response.statusCode}');
                debugPrint('UPDATE CATEGORY BODY => ${response.body}');

                if (response.statusCode == 409) {
                  throw Exception('Ya existe una categoría con ese nombre');
                }

                if (response.statusCode >= 400) {
                  throw Exception(
                    'No se pudo renombrar la categoría: ${response.statusCode} ${response.body}',
                  );
                }

                updatedName = name;

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (e) {
                debugPrint('Error renaming category: $e');

                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                  });
                }

                _showSnack('No se pudo renombrar la categoría');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Renombrar categoría'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _EditorLabel('Nombre'),
                    const SizedBox(height: 8),
                    _EditorField(controller: nameController),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                  ),
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(submitting ? 'Guardando...' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
    });

    if (updatedName == null || !mounted) return;

    final wasSelected = _selectedCategory == category.name;

    await _loadProducts();

    if (!mounted) return;

    if (wasSelected) {
      setState(() {
        _selectedCategory = updatedName!;
      });
      _ensureSelection();
    }

    _showSnack('Categoría renombrada');
  }

  Future<void> _deleteCategory(MenuCategoryView category) async {
    if (category.id.isEmpty || category.name == 'Todas') return;

    if (category.count > 0) {
      _showSnack('No se puede eliminar una categoría con platos activos');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Eliminar categoría'),
              content: Text(
                '¿Seguro que deseas eliminar "${category.name}"?\n\nSolo se permite si no tiene platos activos.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB42318),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Eliminar'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/products/categories/${category.id}'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      debugPrint('DELETE CATEGORY RESPONSE => ${response.statusCode}');
      debugPrint('DELETE CATEGORY BODY => ${response.body}');

      if (response.statusCode == 409) {
        _showSnack('No se puede eliminar una categoría con platos activos');
        return;
      }

      if (response.statusCode >= 400) {
        throw Exception(
          'No se pudo eliminar la categoría: ${response.statusCode} ${response.body}',
        );
      }

      if (!mounted) return;

      if (_selectedCategory == category.name) {
        setState(() {
          _selectedCategory = 'Todas';
        });
      }

      await _loadProducts();

      if (!mounted) return;
      _showSnack('Categoría eliminada');
    } catch (e) {
      debugPrint('Error deleting category: $e');
      _showSnack('No se pudo eliminar la categoría');
    }
  }

  Future<void> _openCreateProductDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();
    final categoryController = TextEditingController();

    PlatformFile? selectedFile;
    bool visible = true;
    bool submitting = false;

    final createdProductId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result == null || result.files.isEmpty) return;
              if (!dialogContext.mounted) return;

              setLocalState(() {
                selectedFile = result.files.first;
              });
            }

            Future<void> submit() async {
              if (submitting) return;

              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              final category = categoryController.text.trim();
              final price = double.tryParse(priceController.text.trim());

              if (name.isEmpty) {
                _showSnack('El nombre es requerido');
                return;
              }

              if (price == null) {
                _showSnack('Precio inválido');
                return;
              }

              try {
                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = true;
                  });
                }

                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse('$baseUrl/api/products'),
                );

                request.headers.addAll(const {
                  'Accept': 'application/json',
                  'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
                });

                request.fields['name'] = name;
                request.fields['description'] = description;
                request.fields['category'] = category;
                request.fields['price'] = price.toStringAsFixed(2);
                request.fields['isActive'] = visible.toString();

                if (selectedFile != null) {
                  if (selectedFile!.path != null) {
                    request.files.add(
                      await http.MultipartFile.fromPath(
                        'imageFile',
                        selectedFile!.path!,
                        filename: selectedFile!.name,
                      ),
                    );
                  } else if (selectedFile!.bytes != null) {
                    request.files.add(
                      http.MultipartFile.fromBytes(
                        'imageFile',
                        selectedFile!.bytes!,
                        filename: selectedFile!.name,
                      ),
                    );
                  }
                }

                final streamed = await request.send();
                final response = await http.Response.fromStream(streamed);

                debugPrint('CREATE PRODUCT RESPONSE => ${response.statusCode}');
                debugPrint('CREATE PRODUCT BODY => ${response.body}');

                if (response.statusCode >= 400) {
                  throw Exception('No se pudo crear el plato');
                }

                final decoded = jsonDecode(response.body);
                final data = decoded is Map<String, dynamic>
                    ? decoded
                    : <String, dynamic>{};

                final productJson = data['product'];
                if (productJson is! Map<String, dynamic>) {
                  throw Exception('Respuesta inválida al crear producto');
                }

                final created = MenuProduct.fromJson(productJson);

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(created.id);
                }
              } catch (e) {
                debugPrint('Error creating plato: $e');
                _showSnack('No se pudo crear el plato');

                if (dialogContext.mounted) {
                  setLocalState(() {
                    submitting = false;
                  });
                }
              }
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 140, vertical: 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                    MediaQuery.sizeOf(context).width < 1100 ? 22 : 30),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Agregar nuevo plato',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _EditorLabel('Nombre'),
                        const SizedBox(height: 8),
                        _EditorField(controller: nameController),
                        const SizedBox(height: 16),
                        const _EditorLabel('Descripción'),
                        const SizedBox(height: 8),
                        _EditorField(
                          controller: descriptionController,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _EditorLabel('Precio'),
                                  const SizedBox(height: 8),
                                  _EditorField(
                                    controller: priceController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const _EditorLabel('Categoría'),
                                  const SizedBox(height: 8),
                                  _EditorField(controller: categoryController),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Mostrar plato',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ),
                              Switch(
                                value: visible,
                                onChanged: submitting
                                    ? null
                                    : (value) {
                                        setLocalState(() {
                                          visible = value;
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _EditorLabel('Imagen desde el dispositivo'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selectedFile?.name ??
                                      'No has seleccionado ninguna imagen',
                                  style: const TextStyle(
                                    color: Color(0xFF475467),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: submitting ? null : pickFile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF3F4F6),
                                  foregroundColor: const Color(0xFF111827),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('Elegir archivo'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: submitting ? null : submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111827),
                                foregroundColor: Colors.white,
                              ),
                              icon: submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.add_rounded),
                              label: Text(
                                submitting ? 'Creando...' : 'Crear plato',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      descriptionController.dispose();
      priceController.dispose();
      categoryController.dispose();
    });

    if (createdProductId == null || createdProductId.isEmpty || !mounted) {
      return;
    }

    await _loadProducts();

    if (!mounted) return;

    MenuProduct? created;
    for (final product in _products) {
      if (product.id == createdProductId) {
        created = product;
        break;
      }
    }

    if (created != null) {
      setState(() {
        _selectedCategory = _normalizedCategoryLabel(created!.category);
        _applySelectedProduct(created!);
      });
    }

    _showSnack('Plato creado');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1060;
          final veryCompact = constraints.maxWidth < 900;
          final padding = compact ? 12.0 : 20.0;
          final gap = compact ? 12.0 : 18.0;
          final panelRadius = compact ? 22.0 : 30.0;

          Widget productsPanel = Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(panelRadius),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x100F172A),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 22,
                    compact ? 14 : 20,
                    compact ? 14 : 22,
                    compact ? 10 : 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedCategory == 'Todas'
                              ? 'Platos'
                              : _selectedCategory,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 20 : 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF111827),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 10 : 12,
                          vertical: compact ? 6 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_filteredProducts.length} visibles',
                          style: TextStyle(
                            color: const Color(0xFF344054),
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 12 : 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _hasError
                          ? _MenuErrorState(onRetry: _loadProducts)
                          : _filteredProducts.isEmpty
                              ? _MenuEmptyState(
                                  hasSearch: _searchQuery.isNotEmpty,
                                )
                              : RefreshIndicator(
                                  onRefresh: _loadProducts,
                                  child: ListView.separated(
                                    padding: EdgeInsets.all(compact ? 10 : 16),
                                    itemCount: _filteredProducts.length,
                                    separatorBuilder: (_, __) =>
                                        SizedBox(height: compact ? 10 : 14),
                                    itemBuilder: (context, index) {
                                      final product = _filteredProducts[index];

                                      return GestureDetector(
                                        onTap: () => _selectProduct(product),
                                        child: _MenuCard(
                                          product: product,
                                          isSelected: _selectedProduct?.id ==
                                              product.id,
                                          onToggleStatus: () =>
                                              _toggleStatus(product),
                                          onDelete: () =>
                                              _deleteProduct(product),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
          );

          Widget editorPanel = _selectedProduct == null
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(panelRadius),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x100F172A),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Selecciona un plato para editarlo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                )
              : _ProductEditorPanel(
                  product: _selectedProduct!,
                  nameController: _nameController,
                  descriptionController: _descriptionController,
                  priceController: _priceController,
                  categoryController: _categoryController,
                  isVisible: _isVisible,
                  isSaving: _saving,
                  isSavingImage: _savingImage,
                  onChangedVisible: (value) {
                    setState(() {
                      _isVisible = value;
                    });
                  },
                  onSave: _saveProduct,
                  onPickAndUploadImage: _pickAndUploadImage,
                  onAddModifierGroup: () {
                    final product = _selectedProduct;
                    if (product != null) {
                      _createModifierGroup(product);
                    }
                  },
                  onAddModifierOption: _createModifierOption,
                  onEditModifierGroup: _editModifierGroup,
                  onDeleteModifierGroup: _deleteModifierGroup,
                  onEditModifierOption: _editModifierOption,
                  onDeleteModifierOption: _deleteModifierOption,
                );

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MenuHeader(
                  controller: _searchController,
                  onCreate: _openCreateProductDialog,
                ),
                SizedBox(height: compact ? 10 : 14),
                _CategoryTabsBar(
                  categories: categories,
                  selectedCategory: _selectedCategory,
                  onSelected: (value) {
                    setState(() {
                      _selectedCategory = value;
                    });
                    _ensureSelection();
                  },
                  onRenameCategory: _renameCategory,
                  onDeleteCategory: _deleteCategory,
                ),
                SizedBox(height: compact ? 10 : 14),
                Expanded(
                  child: veryCompact && _selectedProduct != null
                      ? Column(
                          children: [
                            Expanded(flex: 5, child: productsPanel),
                            SizedBox(height: gap),
                            Expanded(flex: 6, child: editorPanel),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              flex: compact ? 11 : 7,
                              child: productsPanel,
                            ),
                            SizedBox(width: gap),
                            Expanded(
                              flex: compact ? 10 : 6,
                              child: editorPanel,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String normalizeImageUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }

  if (trimmed.startsWith('http://')) {
    return trimmed.replaceFirst('http://', 'https://');
  }

  if (trimmed.startsWith('/')) {
    return 'https://gopicaderabackend-production.up.railway.app$trimmed';
  }

  return trimmed;
}

class _SafeNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget fallback;

  const _SafeNetworkImage({
    required this.imageUrl,
    required this.fit,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeImageUrl(imageUrl);

    if (normalized.isEmpty) {
      debugPrint('IMAGE EMPTY => "$imageUrl"');
      return fallback;
    }

    debugPrint('IMAGE LOAD => $normalized');

    return AppNetworkImage(
      imageUrl: normalized,
      fit: fit,
    );
  }
}

class _MenuHeader extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onCreate;

  const _MenuHeader({
    required this.controller,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1060;
        final searchWidth = compact ? 250.0 : 320.0;

        return SizedBox(
          height: compact ? 46 : 54,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Menú',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 30 : 38,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: compact ? -1.0 : -1.6,
                    height: 1.0,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: searchWidth,
                  minWidth: compact ? 210 : 260,
                ),
                child: Container(
                  height: compact ? 44 : 50,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(compact ? 14 : 16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C0F172A),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: const Color(0xFF98A2B3),
                        size: compact ? 21 : 24,
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: compact
                                ? 'Buscar'
                                : 'Buscar producto o categoría',
                            hintStyle: TextStyle(
                              color: const Color(0xFF98A2B3),
                              fontSize: compact ? 14 : 16,
                              fontWeight: FontWeight.w600,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: TextStyle(
                            fontSize: compact ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              SizedBox(
                height: compact ? 44 : 50,
                child: ElevatedButton.icon(
                  onPressed: onCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(compact ? 16 : 22),
                    ),
                    padding:
                        EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
                  ),
                  icon: Icon(Icons.add_rounded, size: compact ? 20 : 24),
                  label: Text(
                    compact ? 'Nuevo' : 'Nuevo plato',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryTabsBar extends StatelessWidget {
  final List<MenuCategoryView> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;
  final ValueChanged<MenuCategoryView> onRenameCategory;
  final ValueChanged<MenuCategoryView> onDeleteCategory;

  const _CategoryTabsBar({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
    required this.onRenameCategory,
    required this.onDeleteCategory,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1060;
        final cardWidth = compact ? 180.0 : 220.0;
        final barHeight = compact ? 120.0 : 130.0;

        return SizedBox(
          height: barHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => SizedBox(width: compact ? 8 : 10),
            itemBuilder: (context, index) {
              final category = categories[index];
              final selected = category.name == selectedCategory;

              return GestureDetector(
                onTap: () => onSelected(category.name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: cardWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(compact ? 16 : 20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF111827)
                          : const Color(0xFFE5E7EB),
                      width: selected ? 1.8 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x100F172A),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 8 : 10),
                    child: Row(
                      children: [
                        _CategoryImage(imageUrl: category.imageUrl),
                        SizedBox(width: compact ? 8 : 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.name.replaceAll('>', ' > '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: compact ? 12 : 15,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              SizedBox(height: compact ? 5 : 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 7 : 10,
                                  vertical: compact ? 4 : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${category.count}',
                                  style: TextStyle(
                                    fontSize: compact ? 10 : 12,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF344054),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (category.name != 'Todas' && category.id.isNotEmpty)
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              if (value == 'rename') {
                                onRenameCategory(category);
                              }
                              if (value == 'delete') {
                                onDeleteCategory(category);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Renombrar'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Eliminar'),
                              ),
                            ],
                            child: Padding(
                              padding: EdgeInsets.all(compact ? 2 : 6),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: compact ? 18 : 24,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CategoryImage extends StatelessWidget {
  final String imageUrl;

  const _CategoryImage({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1100;
    return Container(
      width: compact ? 52 : 72,
      height: compact ? 52 : 72,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(compact ? 14 : 22),
      ),
      clipBehavior: Clip.antiAlias,
      child: _SafeNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        fallback: Icon(Icons.fastfood_rounded,
            size: MediaQuery.sizeOf(context).width < 1100 ? 24 : 36),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final MenuProduct product;
  final bool isSelected;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _MenuCard({
    required this.product,
    required this.isSelected,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final tight = constraints.maxWidth < 430;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF111827)
                  : const Color(0xFFE5E7EB),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductThumb(imageUrl: product.imageUrl),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 4),
                    Text(
                      product.description.isEmpty
                          ? 'Sin descripción'
                          : product.description,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 12 : 14,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (product.category.isNotEmpty && !tight)
                          _MiniBadge(
                            label: product.category,
                            bg: const Color(0xFFF3F4F6),
                            fg: const Color(0xFF344054),
                          ),
                        _MiniBadge(
                          label: product.isActive ? 'Visible' : 'Oculto',
                          bg: product.isActive
                              ? const Color(0xFFEAF8EE)
                              : const Color(0xFFFEE4E2),
                          fg: product.isActive
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB42318),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'toggle') {
                        onToggleStatus();
                      }
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          product.isActive ? 'Ocultar plato' : 'Mostrar plato',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar'),
                      ),
                    ],
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: compact ? 20 : 24,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 6),
                  Text(
                    '\$${product.price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: compact ? 16 : 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String imageUrl;

  const _ProductThumb({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1100;
    return Container(
      width: compact ? 52 : 62,
      height: compact ? 52 : 62,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
      ),
      clipBehavior: Clip.antiAlias,
      child: _SafeNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        fallback: Icon(Icons.fastfood_rounded,
            size: MediaQuery.sizeOf(context).width < 1100 ? 24 : 30),
      ),
    );
  }
}

class _ProductEditorPanel extends StatelessWidget {
  final MenuProduct product;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController priceController;
  final TextEditingController categoryController;
  final bool isVisible;
  final bool isSaving;
  final bool isSavingImage;
  final ValueChanged<bool> onChangedVisible;
  final VoidCallback onSave;
  final VoidCallback onPickAndUploadImage;
  final VoidCallback onAddModifierGroup;
  final ValueChanged<MenuModifierGroup> onAddModifierOption;
  final ValueChanged<MenuModifierGroup> onEditModifierGroup;
  final ValueChanged<MenuModifierGroup> onDeleteModifierGroup;
  final void Function(MenuModifierGroup group, MenuModifierOption option)
      onEditModifierOption;
  final void Function(MenuModifierGroup group, MenuModifierOption option)
      onDeleteModifierOption;

  const _ProductEditorPanel({
    required this.product,
    required this.nameController,
    required this.descriptionController,
    required this.priceController,
    required this.categoryController,
    required this.isVisible,
    required this.isSaving,
    required this.isSavingImage,
    required this.onChangedVisible,
    required this.onSave,
    required this.onPickAndUploadImage,
    required this.onAddModifierGroup,
    required this.onAddModifierOption,
    required this.onEditModifierGroup,
    required this.onDeleteModifierGroup,
    required this.onEditModifierOption,
    required this.onDeleteModifierOption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 1100 ? 14 : 22,
              MediaQuery.sizeOf(context).width < 1100 ? 14 : 20,
              MediaQuery.sizeOf(context).width < 1100 ? 14 : 22,
              MediaQuery.sizeOf(context).width < 1100 ? 12 : 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Editar plato',
                    style: TextStyle(
                      fontSize:
                          MediaQuery.sizeOf(context).width < 1100 ? 19 : 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 1100 ? 10 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: _EditorImage(imageUrl: product.imageUrl),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSavingImage ? null : onPickAndUploadImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F4F6),
                        foregroundColor: const Color(0xFF111827),
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: isSavingImage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.photo_library_rounded),
                      label: Text(
                        isSavingImage ? 'Actualizando...' : 'Cambiar imagen',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _EditorLabel('Nombre'),
                  const SizedBox(height: 8),
                  _EditorField(controller: nameController),
                  const SizedBox(height: 16),
                  const _EditorLabel('Descripción'),
                  const SizedBox(height: 8),
                  _EditorField(
                    controller: descriptionController,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  const _EditorLabel('Precio'),
                  const SizedBox(height: 8),
                  _EditorField(
                    controller: priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  const _EditorLabel('Categoría'),
                  const SizedBox(height: 8),
                  _EditorField(controller: categoryController),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Mostrar plato',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        Switch(
                          value: isVisible,
                          onChanged: onChangedVisible,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _ModifierGroupsSection(
                    groups: product.modifierGroups,
                    onAddGroup: onAddModifierGroup,
                    onAddOption: onAddModifierOption,
                    onEditGroup: onEditModifierGroup,
                    onDeleteGroup: onDeleteModifierGroup,
                    onEditOption: onEditModifierOption,
                    onDeleteOption: onDeleteModifierOption,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  isSaving ? 'Guardando...' : 'Guardar cambios',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModifierGroupsSection extends StatelessWidget {
  final List<MenuModifierGroup> groups;
  final VoidCallback onAddGroup;
  final ValueChanged<MenuModifierGroup> onAddOption;
  final ValueChanged<MenuModifierGroup> onEditGroup;
  final ValueChanged<MenuModifierGroup> onDeleteGroup;
  final void Function(MenuModifierGroup group, MenuModifierOption option)
      onEditOption;
  final void Function(MenuModifierGroup group, MenuModifierOption option)
      onDeleteOption;

  const _ModifierGroupsSection({
    required this.groups,
    required this.onAddGroup,
    required this.onAddOption,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onEditOption,
    required this.onDeleteOption,
  });

  String _selectionLabel(MenuModifierGroup group) {
    if (group.selectionType == 'multiple') {
      return 'Múltiple';
    }

    return 'Única';
  }

  String _rulesLabel(MenuModifierGroup group) {
    final requiredLabel = group.isRequired ? 'Obligatorio' : 'Opcional';
    return '$requiredLabel · mín ${group.minSelect} · máx ${group.maxSelect}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Opciones personalizables',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: onAddGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Grupo',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Configura grupos, selección única o múltiple, mínimos, máximos y precios extra.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          if (groups.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Text(
                'Este plato todavía no tiene opciones personalizables.',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Column(
              children: groups
                  .map(
                    (group) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _MiniBadge(
                                          label: _selectionLabel(group),
                                          bg: const Color(0xFFEFF6FF),
                                          fg: const Color(0xFF175CD3),
                                        ),
                                        _MiniBadge(
                                          label: _rulesLabel(group),
                                          bg: group.isRequired
                                              ? const Color(0xFFFFF7ED)
                                              : const Color(0xFFF3F4F6),
                                          fg: group.isRequired
                                              ? const Color(0xFFC2410C)
                                              : const Color(0xFF344054),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => onAddOption(group),
                                    icon:
                                        const Icon(Icons.add_rounded, size: 18),
                                    label: const Text('Opción'),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        onEditGroup(group);
                                      }
                                      if (value == 'delete') {
                                        onDeleteGroup(group);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Editar grupo'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Eliminar grupo'),
                                      ),
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.more_horiz_rounded),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (group.options.isEmpty)
                            const Text(
                              'Sin opciones todavía.',
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            Column(
                              children: group.options
                                  .map(
                                    (option) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              option.name,
                                              style: const TextStyle(
                                                color: Color(0xFF111827),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            option.priceAdjustment > 0
                                                ? '+\$${option.priceAdjustment.toStringAsFixed(2)}'
                                                : '+\$0.00',
                                            style: const TextStyle(
                                              color: Color(0xFF15803D),
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                onEditOption(group, option);
                                              }
                                              if (value == 'delete') {
                                                onDeleteOption(group, option);
                                              }
                                            },
                                            itemBuilder: (context) => const [
                                              PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Editar opción'),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Eliminar opción'),
                                              ),
                                            ],
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.more_horiz_rounded,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _EditorImage extends StatelessWidget {
  final String imageUrl;

  const _EditorImage({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1100;
    return Container(
      width: compact ? 104 : 132,
      height: compact ? 104 : 132,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
      ),
      clipBehavior: Clip.antiAlias,
      child: _SafeNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        fallback: const Icon(Icons.image_not_supported_rounded, size: 42),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _MiniBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EditorLabel extends StatelessWidget {
  final String text;

  const _EditorLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF111827),
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;

  const _EditorField({
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF111827)),
        ),
      ),
    );
  }
}

class _MenuEmptyState extends StatelessWidget {
  final bool hasSearch;

  const _MenuEmptyState({
    required this.hasSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.restaurant_menu_rounded,
              size: 54,
              color: const Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? 'No encontramos platos que coincidan con tu búsqueda'
                  : 'Todavía no hay platos cargados',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Prueba con otro nombre o categoría.'
                  : 'Los platos del menú aparecerán aquí.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _MenuErrorState({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 54,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            const Text(
              'No se pudo cargar el menú',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa la conexión con el backend y vuelve a intentar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () async {
                await onRetry();
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class MenuProduct {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String categoryId;
  final bool isActive;
  final String imageUrl;
  final String? wooProductId;
  final List<MenuModifierGroup> modifierGroups;

  const MenuProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.categoryId,
    required this.isActive,
    required this.imageUrl,
    required this.wooProductId,
    required this.modifierGroups,
  });

  factory MenuProduct.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawPrice = json['price'];
    final rawIsActive = json['isActive'];
    final rawWooProductId = json['wooProductId'];
    final rawCategory = json['category'];

    String categoryId = (json['categoryId'] ?? '').toString();
    if (categoryId.trim().isEmpty && rawCategory is Map) {
      categoryId = (rawCategory['id'] ?? '').toString();
    }

    String categoryName = (json['categoryName'] ?? '').toString();
    if (categoryName.trim().isEmpty) {
      if (rawCategory is Map) {
        categoryName = (rawCategory['name'] ?? 'Sin categoría').toString();
      } else {
        categoryName = (rawCategory ?? 'Sin categoría').toString();
      }
    }

    final rawModifierGroups = json['modifierGroups'];
    final modifierGroups = rawModifierGroups is List
        ? rawModifierGroups
            .whereType<Map>()
            .map(
                (e) => MenuModifierGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <MenuModifierGroup>[];

    return MenuProduct(
      id: (rawId ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      price: rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse('$rawPrice') ?? 0,
      category: categoryName.trim().isEmpty ? 'Sin categoría' : categoryName,
      categoryId: categoryId,
      isActive: rawIsActive == true ||
          rawIsActive == 1 ||
          rawIsActive.toString().toLowerCase() == 'true',
      imageUrl: (json['imageUrl'] ?? '').toString(),
      wooProductId: rawWooProductId == null ? null : rawWooProductId.toString(),
      modifierGroups: modifierGroups,
    );
  }
}

class MenuModifierGroup {
  final String id;
  final String name;
  final String selectionType;
  final int minSelect;
  final int maxSelect;
  final bool isRequired;
  final bool isActive;
  final List<MenuModifierOption> options;

  const MenuModifierGroup({
    required this.id,
    required this.name,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.isRequired,
    required this.isActive,
    required this.options,
  });

  factory MenuModifierGroup.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];

    return MenuModifierGroup(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Grupo sin nombre').toString(),
      selectionType: (json['selectionType'] ?? 'single').toString(),
      minSelect: ((json['minSelect'] ?? 0) as num).toInt(),
      maxSelect: ((json['maxSelect'] ?? 1) as num).toInt(),
      isRequired: json['isRequired'] == true ||
          json['isRequired'] == 1 ||
          json['isRequired'].toString().toLowerCase() == 'true',
      isActive: json['isActive'] != false,
      options: rawOptions is List
          ? rawOptions
              .whereType<Map>()
              .map(
                (e) => MenuModifierOption.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
          : <MenuModifierOption>[],
    );
  }
}

class MenuModifierOption {
  final String id;
  final String name;
  final double priceAdjustment;
  final bool isActive;

  const MenuModifierOption({
    required this.id,
    required this.name,
    required this.priceAdjustment,
    required this.isActive,
  });

  factory MenuModifierOption.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['priceAdjustment'];

    return MenuModifierOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Opción').toString(),
      priceAdjustment: rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse('$rawPrice') ?? 0,
      isActive: json['isActive'] != false,
    );
  }
}

class MenuCategoryView {
  final String id;
  final String name;
  final String imageUrl;
  final int count;

  const MenuCategoryView({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.count,
  });
}
