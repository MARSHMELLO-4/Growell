import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:growell/Home/homeScreen.dart';
import 'package:http/http.dart' as http;

class Diseasedetailspage extends StatefulWidget {
  final Map<String, dynamic>? res;

  const Diseasedetailspage({super.key, required this.res});

  @override
  State<Diseasedetailspage> createState() => _DiseasedetailspageState();
}

class _DiseasedetailspageState extends State<Diseasedetailspage> {
  String description = 'Fetching description...';
  String treatment = 'Fetching treatment...';
  String otherNames = 'N/A';
  String family = 'N/A';
  String hostPlants = 'N/A';
  List<dynamic> additionalImages = [];

  @override
  void initState() {
    super.initState();
    fetchAdditionalData();
  }

  Future<void> fetchAdditionalData() async {
    final result = widget.res;
    final disease = result?['result']?['disease']?['suggestions']?[0];
    final diseaseName = disease?['name'];
    final scientificName = disease?['scientific_name'];

    if (diseaseName != null && scientificName != null) {
      bool found = false;

      for (int page = 1; page <= 4; page++) {
        final url = Uri.parse(
            'https://perenual.com/api/pest-disease-list?key=sk-LMv667de56d689dd96348&page=$page');
        try {
          final response = await http.get(url);
          print("Response status code: ${response.statusCode}");
          print("Response body: ${response.body}");

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            print("Decoded data: $data");

            if (data.containsKey('data')) {
              final diseases = data['data'] as List;
              print("Diseases fetched: ${diseases.length}");

              final matchedDisease = diseases.firstWhere(
                (d) {
                  final commonNameMatch =
                      d['common_name'].toString().toLowerCase() ==
                          diseaseName.toLowerCase();
                  final scientificNameMatch =
                      d['scientific_name'].toString().toLowerCase() ==
                          scientificName.toLowerCase();
                  print(
                      "Checking disease: ${d['common_name']} (${d['scientific_name']})");
                  print(
                      "Match result: commonNameMatch=$commonNameMatch, scientificNameMatch=$scientificNameMatch");
                  return commonNameMatch || scientificNameMatch;
                },
                orElse: () => {},
              );

              if (matchedDisease.isNotEmpty) {
                // Extract and format description
                final descriptionList = matchedDisease['description'] as List?;
                final descriptionText = descriptionList
                        ?.map((desc) =>
                            '${desc['subtitle']}\n${desc['description']}')
                        .join('\n\n') ??
                    'No description available';

                // Extract and format treatment
                final solutionList = matchedDisease['solution'] as List?;
                final solutionText = solutionList
                        ?.map((sol) =>
                            '${sol['subtitle']}\n${sol['description']}')
                        .join('\n\n') ??
                    'No treatment available';

                // Extract additional data
                final otherNames =
                    matchedDisease['other_name']?.join(', ') ?? 'N/A';
                final family = matchedDisease['family'] ?? 'N/A';
                final hostPlants = matchedDisease['host']?.join(', ') ?? 'N/A';
                final images = matchedDisease['images'] as List? ?? [];

                setState(() {
                  description = descriptionText;
                  treatment = solutionText;
                  this.otherNames = otherNames;
                  this.family = family;
                  this.hostPlants = hostPlants;
                  additionalImages = images;
                });
                found = true;
                break; // Exit the loop if a match is found
              }
            } else {
              print("No 'data' field in the response");
            }
          } else {
            setState(() {
              description =
                  'Failed to fetch description: Status code ${response.statusCode}';
              treatment =
                  'Failed to fetch treatment: Status code ${response.statusCode}';
            });
            break; // Exit the loop if there's an error
          }
        } catch (e) {
          print("Error fetching data: $e");
          setState(() {
            description = 'Failed to fetch description: $e';
            treatment = 'Failed to fetch treatment: $e';
          });
          break; // Exit the loop if there's an exception
        }
      }

      if (!found) {
        setState(() {
          description = 'No additional description found';
          treatment = 'No additional treatment found';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.res;
    final imageUrl = result?['input']?['images']?[0] ?? '';
    final disease = result?['result']?['disease']?['suggestions']?[0];
    final diseaseName = disease?['name'] ?? 'Unknown';
    final probability = disease?['probability'] ?? 0.0;
    final scientificName = disease?['scientific_name'] ?? 'Unknown';
    final commonNames =
        disease?['details']?['common_names']?.join(', ') ?? 'Unknown';
    final similarImages = disease?['similar_images'] ?? [];

    return Scaffold(
      appBar: AppBar(
          title: Text('Disease Details',
              style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Disease Image
            imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.network(imageUrl,
                        height: 250, width: double.infinity, fit: BoxFit.cover),
                  )
                : SizedBox(
                    height: 250,
                    child: Center(child: Text('No Image Available'))),
            SizedBox(height: 20),

            // Disease Details
            buildDetailCard('Disease', diseaseName),
            buildDetailCard('Scientific Name', scientificName),
            buildDetailCard('Common Names', commonNames),
            buildDetailCard(
                'Probability', '${(probability * 100).toStringAsFixed(2)}%'),
            buildDetailCard('Other Names', otherNames),
            buildDetailCard('Family', family),
            buildDetailCard('Host Plants', hostPlants),

            // Description
            buildSectionTitle('Description'),
            buildDescriptionCard(description),

            // Treatment
            buildSectionTitle('Treatment'),
            buildDescriptionCard(treatment),

            // Additional Images
            buildSectionTitle('Additional Images'),
            if (additionalImages.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8.0,
                  mainAxisSpacing: 8.0,
                ),
                itemCount: additionalImages.length,
                itemBuilder: (context, index) {
                  final image = additionalImages[index];
                  print("Loading image: ${image['regular_url']}");
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10.0),
                    child: Image.network(
                      image['regular_url'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        print("Failed to load image: ${image['regular_url']}");
                        return Icon(Icons.broken_image,
                            size: 100, color: Colors.grey); // Fallback widget
                      },
                    ),
                  );
                },
              )
            else
              Text('No additional images available',
                  style: TextStyle(fontSize: 16)),

            // Similar Images
            buildSectionTitle('Similar Images'),
            if (similarImages.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8.0,
                  mainAxisSpacing: 8.0,
                ),
                itemCount: similarImages.length,
                itemBuilder: (context, index) {
                  final image = similarImages[index];
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10.0),
                        child: Image.network(image['url'],
                            height: 100, width: 100, fit: BoxFit.cover),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Similarity: ${(image['similarity'] * 100).toStringAsFixed(2)}%',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  );
                },
              )
            else
              Text('No similar images available',
                  style: TextStyle(fontSize: 16)),

            // Home Button
            SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (context) => HomeScreen()));
                },
                icon: Icon(Icons.home),
                label: Text('Home'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  textStyle: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDetailCard(String title, String value) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Text(title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget buildDescriptionCard(String text) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(text, style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
