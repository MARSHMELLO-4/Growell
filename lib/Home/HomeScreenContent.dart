import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';

class Homescreencontent extends StatefulWidget {
  const Homescreencontent({super.key});

  @override
  State<Homescreencontent> createState() => _HomescreencontentState();
}

class _HomescreencontentState extends State<Homescreencontent> {
  final List<Map<String, dynamic>> farms = [];
  final ImagePicker _picker = ImagePicker();

  void _showFarmForm() {
    final _formKey = GlobalKey<FormState>();
    String name = '';
    String location = '';
    String size = '';
    File? selectedImage;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Add Farm", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTextField("Farm Name", (value) => name = value!),
                      _buildTextField("Location", (value) => location = value!),
                      _buildTextField("Size (Acres)", (value) => size = value!, isNumeric: true),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
                          if (pickedFile != null) {
                            setState(() => selectedImage = File(pickedFile.path));
                          }
                        },
                        icon: const Icon(Icons.image, color: Colors.white),
                        label: const Text("Pick Image"),
                        style: _buttonStyle(),
                      ),
                      const SizedBox(height: 16),
                      selectedImage != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(selectedImage!, height: 150, fit: BoxFit.cover),
                      )
                          : _emptyImageContainer(),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            _dialogButton("Cancel", () => Navigator.of(context).pop(), Colors.red),
            _dialogButton("Add", () {
              if (_formKey.currentState!.validate() && selectedImage != null) {
                _formKey.currentState!.save();
                setState(() {
                  farms.add({"name": name, "location": location, "size": size, "image": selectedImage});
                });
                Navigator.of(context).pop();
              }
            }, Colors.green),
          ],
        );
      },
    );
  }

  void _deleteFarm(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Delete Farm", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to delete this farm?"),
        actions: [
          _dialogButton("Cancel", () => Navigator.of(context).pop(), Colors.grey),
          _dialogButton("Delete", () {
            setState(() => farms.removeAt(index));
            Navigator.of(context).pop();
          }, Colors.red),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Farms", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _showFarmForm,
              style: _buttonStyle(),
              child: const Text("Add Farm", style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: farms.isEmpty
                  ? const Center(child: Text("No farms added yet.", style: TextStyle(fontSize: 18, color: Colors.grey)))
                  : ListView.builder(
                itemCount: farms.length,
                itemBuilder: (context, index) => _farmCard(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _farmCard(int index) {
    return Card(
      elevation: 5,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: farms[index]['image'] != null
                ? Image.file(farms[index]['image'], height: 200, width: double.infinity, fit: BoxFit.cover)
                : _emptyImageContainer(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(farms[index]['name'], style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("Location: ${farms[index]['location']}", style: TextStyle(fontSize: 16, color: Colors.grey[700])),
                Text("Size: ${farms[index]['size']} acres", style: TextStyle(fontSize: 16, color: Colors.grey[700])),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 28),
              onPressed: () => _deleteFarm(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyImageContainer() {
    return Container(
      height: 150,
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
      child: const Center(child: Text("No image selected", style: TextStyle(fontSize: 16))),
    );
  }

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)));

  Widget _dialogButton(String text, VoidCallback onPressed, Color color) => TextButton(onPressed: onPressed, child: Text(text, style: TextStyle(fontSize: 16, color: color)));

  Widget _buildTextField(String label, Function(String?) onSave, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        validator: (value) => value!.isEmpty ? "Enter $label" : null,
        onSaved: onSave,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      ),
    );
  }
}