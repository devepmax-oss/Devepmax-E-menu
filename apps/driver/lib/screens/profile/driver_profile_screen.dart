import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/driver_models.dart';
import '../../services/driver_api_service.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({
    super.key,
    required this.driver,
  });

  final DriverProfile? driver;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  DriverProfile? _driver;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _driver = widget.driver;
  }

  @override
  void didUpdateWidget(covariant DriverProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.driver?.id != widget.driver?.id ||
        oldWidget.driver?.updatedKey != widget.driver?.updatedKey) {
      setState(() => _driver = widget.driver);
    }
  }

  String _lastSeenText(DateTime? date) {
    if (date == null) return 'Sin reporte reciente';

    final diff = DateTime.now().difference(date.toLocal());

    if (diff.inSeconds < 60) return 'Hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';

    return '${date.toLocal()}';
  }

  Future<void> _pickAndUploadPhoto() async {
    final current = _driver;
    if (current == null || _uploadingPhoto) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Cambiar foto',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Elegir de galería'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1200,
    );

    if (picked == null) return;

    try {
      setState(() => _uploadingPhoto = true);

      final updated = await DriverApiService.instance.uploadProfilePhoto(
        driverId: current.id,
        imageFile: File(picked.path),
      );

      if (!mounted) return;

      setState(() => _driver = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo subir la foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _openEditProfile() async {
    final current = _driver;
    if (current == null || _saving) return;

    final nameController = TextEditingController(text: current.name);
    final phoneController = TextEditingController(text: current.phone);
    final emailController = TextEditingController(text: current.email ?? '');
    final vehicleTypeController =
        TextEditingController(text: current.vehicleType ?? '');
    final vehiclePlateController =
        TextEditingController(text: current.vehiclePlate ?? '');
    final vehicleColorController =
        TextEditingController(text: current.vehicleColor ?? '');

    final result = await showModalBottomSheet<_ProfileEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _EditProfileSheet(
            nameController: nameController,
            phoneController: phoneController,
            emailController: emailController,
            vehicleTypeController: vehicleTypeController,
            vehiclePlateController: vehiclePlateController,
            vehicleColorController: vehicleColorController,
          ),
        );
      },
    );

    if (result == null) return;

    try {
      setState(() => _saving = true);

      final updated = await DriverApiService.instance.updateProfile(
        driverId: current.id,
        name: result.name,
        phone: result.phone,
        email: result.email,
        vehicleType: result.vehicleType,
        vehiclePlate: result.vehiclePlate,
        vehicleColor: result.vehicleColor,
      );

      if (!mounted) return;

      setState(() => _driver = updated);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el perfil: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ImageProvider? _profileImageProvider(DriverProfile? driver) {
    final url = driver?.photoUrl?.trim();
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final current = _driver;
    final photoProvider = _profileImageProvider(current);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Perfil',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            IconButton(
              onPressed: current == null || _saving ? null : _openEditProfile,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFFDADA),
                foregroundColor: const Color(0xFF5A3434),
                fixedSize: const Size(56, 56),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F101828),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 58,
                    backgroundColor: const Color(0xFFFFE8E8),
                    backgroundImage: photoProvider,
                    child: photoProvider == null
                        ? const Icon(
                            Icons.person_rounded,
                            size: 62,
                            color: Color(0xFFFF4D4F),
                          )
                        : null,
                  ),
                  GestureDetector(
                    onTap: current == null || _uploadingPhoto
                        ? null
                        : _pickAndUploadPhoto,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22101828),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _uploadingPhoto
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF667085),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                current?.name ?? 'Driver',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF231815),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                current?.phone ?? '',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _AvailableChip(status: current?.status ?? 'offline'),
              const Divider(height: 40),
              _ProfileRow(
                icon: Icons.email_rounded,
                label: 'Email',
                value: current?.email?.trim().isNotEmpty == true
                    ? current!.email!
                    : 'No configurado',
              ),
              _ProfileRow(
                icon: Icons.two_wheeler_rounded,
                label: 'Vehículo',
                value: current?.vehicleType?.trim().isNotEmpty == true
                    ? current!.vehicleType!
                    : 'No configurado',
              ),
              _ProfileRow(
                icon: Icons.confirmation_number_rounded,
                label: 'Placa',
                value: current?.vehiclePlate?.trim().isNotEmpty == true
                    ? current!.vehiclePlate!
                    : 'No configurada',
              ),
              _ProfileRow(
                icon: Icons.palette_rounded,
                label: 'Color',
                value: current?.vehicleColor?.trim().isNotEmpty == true
                    ? current!.vehicleColor!
                    : 'No configurado',
              ),
              _ProfileRow(
                icon: Icons.location_on_rounded,
                label: 'Ubicación',
                value: current?.hasLocation == true
                    ? 'Ubicación activa'
                    : 'Pendiente',
              ),
              _ProfileRow(
                icon: Icons.schedule_rounded,
                label: 'Último reporte',
                value: _lastSeenText(current?.lastSeenAt),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvailableChip extends StatelessWidget {
  const _AvailableChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final available = status == 'available';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: available ? const Color(0xFFEAFBF1) : const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 12,
            color:
                available ? const Color(0xFF128A3C) : const Color(0xFF667085),
          ),
          const SizedBox(width: 10),
          Text(
            available ? 'Disponible para entregar' : 'No disponible',
            style: TextStyle(
              color:
                  available ? const Color(0xFF128A3C) : const Color(0xFF475467),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF98A2B3), size: 26),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends StatelessWidget {
  const _EditProfileSheet({
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.vehicleTypeController,
    required this.vehiclePlateController,
    required this.vehicleColorController,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController vehicleTypeController;
  final TextEditingController vehiclePlateController;
  final TextEditingController vehicleColorController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Editar perfil',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vehicleTypeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Vehículo',
                  hintText: 'Moto, carro, bicicleta...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vehiclePlateController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Placa',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vehicleColorController,
                decoration: const InputDecoration(
                  labelText: 'Color del vehículo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final phone = phoneController.text.trim();
                    final email = emailController.text.trim();
                    final vehicleType = vehicleTypeController.text.trim();
                    final vehiclePlate = vehiclePlateController.text.trim();
                    final vehicleColor = vehicleColorController.text.trim();

                    if (name.isEmpty || phone.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nombre y teléfono son requeridos'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      context,
                      _ProfileEditResult(
                        name: name,
                        phone: phone,
                        email: email.isEmpty ? null : email,
                        vehicleType: vehicleType.isEmpty ? null : vehicleType,
                        vehiclePlate:
                            vehiclePlate.isEmpty ? null : vehiclePlate,
                        vehicleColor:
                            vehicleColor.isEmpty ? null : vehicleColor,
                      ),
                    );
                  },
                  child: const Text(
                    'Guardar cambios',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileEditResult {
  const _ProfileEditResult({
    required this.name,
    required this.phone,
    this.email,
    this.vehicleType,
    this.vehiclePlate,
    this.vehicleColor,
  });

  final String name;
  final String phone;
  final String? email;
  final String? vehicleType;
  final String? vehiclePlate;
  final String? vehicleColor;
}
