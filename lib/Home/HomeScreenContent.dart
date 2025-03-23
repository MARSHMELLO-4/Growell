import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class Homescreencontent extends StatefulWidget {
  @override
  _HomescreencontentState createState() => _HomescreencontentState();
}

class _HomescreencontentState extends State<Homescreencontent> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> farms = [];
  String? userPhoneNumber;

  @override
  void initState() {
    super.initState();
    print("Notifying users about $supabase");
    _fetchUserPhoneNumber();
  }

  Future<String?> _uploadImageToCloudinary(File image) async {
    const String cloudName = "dcpdaxsrs"; // Replace with your Cloudinary cloud name
    const String uploadPreset = "imageStorage"; // Replace with your upload preset

    final Uri uploadUrl = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");

    try {
      var request = http.MultipartRequest("POST", uploadUrl);
      request.fields['upload_preset'] = uploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonData = json.decode(responseData);

      if (response.statusCode == 200) {
        return jsonData['secure_url'];
      } else {
        print("Cloudinary Upload Error: ${jsonData['error']['message']}");
        return null;
      }
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  Future<void> _fetchUserPhoneNumber() async {
    final response = await supabase.auth.getUser();
    if (response.user != null) {
      setState(() {
        userPhoneNumber = response.user!.phone;
      });
      print("User Phone Number: $userPhoneNumber");
      _fetchFarms();
    } else {
      print("User is not logged in!");
    }
  }

  Future<void> _fetchFarms() async {
    if (userPhoneNumber == null) {
      print("No user phone number found!");
      return;
    }

    print("Fetching farms for phone number: $userPhoneNumber");

    try {
      final response = await supabase
          .from('Farms')
          .select()
          .eq('phoneNumber', userPhoneNumber!);

      print("Raw Response: $response");

      if (response != null && response is List) {
        setState(() {
          farms = response.map((farm) => {
            "id": farm["id"],
            "name": farm["farm_name"],
            "location": farm["location"],
            "size": farm["size"],
            "imageUrl": farm["imageUrl"],
          }).toList();
        });

        print("Fetched Farms: $farms");
      } else {
        print("No data found in response");
      }
    } catch (e) {
      print("Exception caught while fetching farms: $e");
    }
  }

  Future<void> _addFarm(String name, String location, String size, File? image) async {
    if (userPhoneNumber == null) {
      print("User phone number is null. Cannot add farm.");
      return;
    }

    String? imageUrl;
    if (image != null) {
      imageUrl = await _uploadImageToCloudinary(image);
      if (imageUrl == null) {
        print("Failed to upload image to Cloudinary.");
        return;
      }
    }

    try {
      final response = await supabase
          .from('Farms')
          .insert({
        "farm_name": name,
        "location": location,
        "size": size,
        "phoneNumber": userPhoneNumber,
        "imageUrl": imageUrl ?? "",
      })
          .select()
          .single();

      if (response != null) {
        setState(() {
          farms.add({
            "id": response["id"],
            "name": response["farm_name"],
            "location": response["location"],
            "size": response["size"],
            "imageUrl": response["imageUrl"],
          });
        });
        print("Farm added successfully!");
      } else {
        print("Failed to add farm: No data returned");
      }
    } catch (e) {
      print("Exception caught while adding farm: $e");
    }
  }

  Future<void> _deleteFarm(int index) async {
    final farmId = farms[index]["id"];
    try {
      final response = await supabase
          .from('Farms')
          .delete()
          .eq('id', farmId);

      if (response == null) {
        print("Farm deleted successfully!");
        setState(() {
          farms.removeAt(index);
        });
      } else {
        print("Supabase Delete Error: $response");
      }
    } catch (e) {
      print("Exception caught while deleting farm: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: farms.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("No farms added yet."),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _showAddFarmDialog(context),
              child: const Text("Add Farm"),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: farms.length + 1,
        itemBuilder: (context, index) {
          if (index == farms.length) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: () => _showAddFarmDialog(context),
                child: const Text("Add Farm"),
              ),
            );
          } else {
            return _farmCard(index);
          }
        },
      ),
    );
  }

  void _showAddFarmDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController locationController = TextEditingController();
    final TextEditingController sizeController = TextEditingController();
    File? selectedImage;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Farm"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Farm Name"),
              ),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(labelText: "Location"),
              ),
              TextField(
                controller: sizeController,
                decoration: const InputDecoration(labelText: "Size (acres)"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    selectedImage = File(image.path);
                  }
                },
                child: const Text("Upload Image"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text;
                final location = locationController.text;
                final size = sizeController.text;

                if (name.isNotEmpty && location.isNotEmpty && size.isNotEmpty) {
                  await _addFarm(name, location, size, selectedImage);
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all fields")),
                  );
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Widget _farmCard(int index) {
    return Card(
      child: Column(
        children: [
          farms[index]['imageUrl'] != null && farms[index]['imageUrl'].isNotEmpty
              ? Image.network(
            farms[index]['imageUrl'],
            height: 200,
            fit: BoxFit.cover,
          )
              : Image.network(
            'https://imgs.search.brave.com/QrrF8yctvnxGKn5UBvuEt1XL7Pv04zXmzQ0y50RN5cY/rs:fit:860:0:0:0/g:ce/aHR0cHM6Ly90NC5m/dGNkbi5uZXQvanBn/LzA3LzkxLzIyLzU5/LzM2MF9GXzc5MTIy/NTkyN19jYVJQUEg5/OUQ2RDFpRm9ua0NS/bUNHemtKUGYzNlFE/dy5qcGc',
            height: 200,
            fit: BoxFit.cover,
          ),
          ListTile(
            title: Text(farms[index]['name']),
            subtitle: Text("Location: ${farms[index]['location']}\nSize: ${farms[index]['size']} acres"),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteFarm(index),
          ),
        ],
      ),
    );
  }
}