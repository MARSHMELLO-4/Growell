import 'dart:convert';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    fetchAdditionalData();
  }

  Future<void> fetchAdditionalData() async {
    final result = widget.res;
    final disease = result?['result']?['disease']?['suggestions']?[0];
    final diseaseName = disease?['name'];

    if (diseaseName != null) {
      final url = Uri.parse('https://perenual.com/api/pest-disease-list?key=sk-LMv667de56d689dd96348&page=1');

      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final diseases = data['data'] as List;

          final matchedDisease = diseases.firstWhere(
                (d) => d['common_name'].toString().toLowerCase() == diseaseName.toLowerCase(),
            orElse: () => {},
          );

          if (matchedDisease.isNotEmpty) {
            // Extract description and treatment
            String descriptionText = matchedDisease['description'] != null
                ? matchedDisease['description'].map((d) => "${d['subtitle']}\n${d['description']}").join("\n\n")
                : 'No description available';

            String treatmentText = matchedDisease['solution'] != null
                ? matchedDisease['solution'].map((s) => "${s['subtitle']}\n${s['description']}").join("\n\n")
                : 'No treatment available';

            setState(() {
              description = descriptionText;
              treatment = treatmentText;
            });
          } else {
            setState(() {
              description = 'No additional description found';
              treatment = 'No additional treatment found';
            });
          }
        } else {
          setState(() {
            description = 'Failed to fetch description';
            treatment = 'Failed to fetch treatment';
          });
        }
      } catch (e) {
        setState(() {
          description = 'Failed to fetch description';
          treatment = 'Failed to fetch treatment';
        });
      }
    } else {
      setState(() {
        description = 'Disease name not found';
        treatment = 'Disease name not found';
      });
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
    final commonNames = disease?['details']?['common_names']?.join(', ') ?? 'Unknown';
    final similarImages = disease?['similar_images'] ?? [];

    return Scaffold(
      appBar: AppBar(title: Text('Disease Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageUrl.isNotEmpty
                ? Image.network(imageUrl, height: 250, width: double.infinity, fit: BoxFit.cover)
                : SizedBox(height: 250, child: Center(child: Text('No Image Available'))),
            SizedBox(height: 20),
            Text('Disease: $diseaseName', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('Scientific Name: $scientificName', style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text('Common Names: $commonNames', style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text('Probability: ${(probability * 100).toStringAsFixed(2)}%', style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            Text('Description:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text(description, style: TextStyle(fontSize: 16)),
            SizedBox(height: 20),
            Text('Treatment:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text(treatment, style: TextStyle(fontSize: 16)),
            SizedBox(height: 20),
            Text('Similar Images:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
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
                      Image.network(image['url'], height: 100, width: 100, fit: BoxFit.cover),
                      SizedBox(height: 5),
                      Text(
                        'Similarity: ${(image['similarity'] * 100).toStringAsFixed(2)}%',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  );
                },
              )
            else
              Text('No similar images available', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
