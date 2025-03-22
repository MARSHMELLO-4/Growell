import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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
          title: const Text("Add Farm"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(labelText: "Farm Name"),
                      validator: (value) =>
                      value!.isEmpty ? "Enter a name" : null,
                      onSaved: (value) => name = value!,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: "Location"),
                      validator: (value) =>
                      value!.isEmpty ? "Enter a location" : null,
                      onSaved: (value) => location = value!,
                    ),
                    TextFormField(
                      decoration:
                      const InputDecoration(labelText: "Size (Acres)"),
                      validator: (value) =>
                      value!.isEmpty ? "Enter size" : null,
                      onSaved: (value) => size = value!,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        final pickedFile =
                        await _picker.pickImage(source: ImageSource.gallery);
                        if (pickedFile != null) {
                          setState(() {
                            selectedImage = File(pickedFile.path);
                          });
                        }
                      },
                      child: const Text("Pick Image"),
                    ),
                    const SizedBox(height: 10),
                    selectedImage != null
                        ? Image.file(selectedImage!, height: 100)
                        : const Text("No image selected"),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate() && selectedImage != null) {
                  _formKey.currentState!.save();
                  setState(() {
                    farms.add({
                      "name": name,
                      "location": location,
                      "size": size,
                      "image": selectedImage
                    });
                  });
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  void _deleteFarm(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Farm"),
        content: const Text("Are you sure you want to delete this farm?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                farms.removeAt(index);
              });
              Navigator.of(context).pop();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Farms")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _showFarmForm,
              child: const Text("Add Farm"),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: farms.isEmpty
                  ? const Center(child: Text("No farms added yet."))
                  : ListView.builder(
                itemCount: farms.length,
                itemBuilder: (context, index) {
                  return Card(
                    elevation: 4,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        farms[index]['image'] != null
                            ? Image.file(farms[index]['image'],
                            height: 150, fit: BoxFit.cover)
                            : const SizedBox(),
                        ListTile(
                          title: Text(
                            farms[index]['name'],
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                              "Location: ${farms[index]['location']}\nSize: ${farms[index]['size']} acres"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteFarm(index),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
