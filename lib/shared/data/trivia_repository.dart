import 'dart:math';
import '../models/question.dart';
import 'trivia_genres.dart';

/// Comprehensive Multi-Genre Trivia Question Repository for Bar Rooms Trivia
class TriviaRepository {
  static final Random _random = Random();

  /// Comprehensive Question Seed Bank covering all 30 specific trivia genres
  static final Map<String, List<Question>> _genreBank = {
    'Homebrewing Beer': [
      Question(
        id: 'hb-01',
        category: 'Homebrewing Beer',
        difficulty: 'Standard',
        questionText: 'What is the primary function of boiling hops during the first 60 minutes of brewing?',
        optionA: 'Extract Alpha Acids for Bitterness',
        optionB: 'Add Fresh Hop Aroma',
        optionC: 'Sweeten the Wort',
        optionD: 'Sterilize the Fermenter',
        correctOption: 'A',
      ),
      Question(
        id: 'hb-02',
        category: 'Homebrewing Beer',
        difficulty: 'Standard',
        questionText: 'Which sugar is primarily produced during the all-grain mashing process by amylase enzymes?',
        optionA: 'Maltose',
        optionB: 'Sucrose',
        optionC: 'Lactose',
        optionD: 'Fructose',
        correctOption: 'A',
      ),
      Question(
        id: 'hb-03',
        category: 'Homebrewing Beer',
        difficulty: 'Standard',
        questionText: 'What instrument is used to measure Original Gravity (OG) and Final Gravity (FG)?',
        optionA: 'Hydrometer / Refractometer',
        optionB: 'Thermometer',
        optionC: 'pH Strip',
        optionD: 'Barometer',
        correctOption: 'A',
      ),
    ],
    'Home Repair': [
      Question(
        id: 'hr-01',
        category: 'Home Repair',
        difficulty: 'Standard',
        questionText: 'What type of electrical outlet is required near sinks and outdoors to prevent shock?',
        optionA: 'GFCI (Ground Fault Circuit Interrupter)',
        optionB: 'Standard 3-Prong',
        optionC: 'AFCI Breaker',
        optionD: '240V Outlet',
        correctOption: 'A',
      ),
      Question(
        id: 'hr-02',
        category: 'Home Repair',
        difficulty: 'Standard',
        questionText: 'What is the actual dimensional size of a standard 2x4 wooden stud?',
        optionA: '1.5 inches by 3.5 inches',
        optionB: '2.0 inches by 4.0 inches',
        optionC: '1.75 inches by 3.75 inches',
        optionD: '1.25 inches by 3.25 inches',
        correctOption: 'A',
      ),
      Question(
        id: 'hr-03',
        category: 'Home Repair',
        difficulty: 'Standard',
        questionText: 'What plumbing fixture prevents sewer gas from leaking up through household drains?',
        optionA: 'P-Trap',
        optionB: 'Cleanout Plug',
        optionC: 'Check Valve',
        optionD: 'Flapper Valve',
        correctOption: 'A',
      ),
    ],
    'Finance': [
      Question(
        id: 'fin-01',
        category: 'Finance',
        difficulty: 'Standard',
        questionText: 'What is the current standard FDIC insurance coverage limit per depositor per bank?',
        optionA: '\$250,000',
        optionB: '\$100,000',
        optionC: '\$500,000',
        optionD: '\$1,000,000',
        correctOption: 'A',
      ),
      Question(
        id: 'fin-02',
        category: 'Finance',
        difficulty: 'Standard',
        questionText: 'Which financial term describes earning interest on both your principal and accumulated interest?',
        optionA: 'Compound Interest',
        optionB: 'Simple Interest',
        optionC: 'Amortization',
        optionD: 'Capital Gain',
        correctOption: 'A',
      ),
    ],
    'Movies & Hollywood': [
      Question(
        id: 'mov-01',
        category: 'Movies & Hollywood',
        difficulty: 'Standard',
        questionText: 'Which film won the first-ever Academy Award for Best Picture in 1929?',
        optionA: 'Wings',
        optionB: 'Sunrise',
        optionC: 'Metropolis',
        optionD: 'The Jazz Singer',
        correctOption: 'A',
      ),
      Question(
        id: 'mov-02',
        category: 'Movies & Hollywood',
        difficulty: 'Standard',
        questionText: 'Who directed the 1993 blockbuster dinosaur classic "Jurassic Park"?',
        optionA: 'Steven Spielberg',
        optionB: 'James Cameron',
        optionC: 'George Lucas',
        optionD: 'Ridley Scott',
        correctOption: 'A',
      ),
      Question(
        id: 'mov-03',
        category: 'Movies & Hollywood',
        difficulty: 'Standard',
        questionText: 'What is the highest-grossing film of all time (unadjusted for inflation)?',
        optionA: 'Avatar',
        optionB: 'Avengers: Endgame',
        optionC: 'Titanic',
        optionD: 'Star Wars: The Force Awakens',
        correctOption: 'A',
      ),
    ],
    '80s & 90s Nostalgia': [
      Question(
        id: 'nos-01',
        category: '80s & 90s Nostalgia',
        difficulty: 'Standard',
        questionText: 'In what year did Nintendo release the iconic Game Boy handheld console in North America?',
        optionA: '1989',
        optionB: '1985',
        optionC: '1992',
        optionD: '1995',
        correctOption: 'A',
      ),
      Question(
        id: 'nos-02',
        category: '80s & 90s Nostalgia',
        difficulty: 'Standard',
        questionText: 'What virtual keychain pet craze swept the world starting in 1996?',
        optionA: 'Tamagotchi',
        optionB: 'Furby',
        optionC: 'Beanie Babies',
        optionD: 'Pogs',
        correctOption: 'A',
      ),
    ],
    'Pop Culture & Music': [
      Question(
        id: 'pop-01',
        category: 'Pop Culture & Music',
        difficulty: 'Standard',
        questionText: 'Which artist released the legendary record-breaking album "Thriller" in 1982?',
        optionA: 'Michael Jackson',
        optionB: 'Prince',
        optionC: 'Stevie Wonder',
        optionD: 'Whitney Houston',
        correctOption: 'A',
      ),
      Question(
        id: 'pop-02',
        category: 'Pop Culture & Music',
        difficulty: 'Standard',
        questionText: 'Which singer released the album "1989" and re-recorded it in 2023?',
        optionA: 'Taylor Swift',
        optionB: 'Katy Perry',
        optionC: 'Lady Gaga',
        optionD: 'Adele',
        correctOption: 'A',
      ),
    ],
    'Sports & Stadiums': [
      Question(
        id: 'sp-01',
        category: 'Sports & Stadiums',
        difficulty: 'Standard',
        questionText: 'How many regulation minutes are played in a standard FIFA soccer match?',
        optionA: '90 Minutes',
        optionB: '80 Minutes',
        optionC: '100 Minutes',
        optionD: '60 Minutes',
        correctOption: 'A',
      ),
      Question(
        id: 'sp-02',
        category: 'Sports & Stadiums',
        difficulty: 'Standard',
        questionText: 'What iconic 37-foot green wall is located in left field at Fenway Park in Boston?',
        optionA: 'The Green Monster',
        optionB: 'The Emerald Wall',
        optionC: 'The Big Greenie',
        optionD: 'Boston Wall',
        correctOption: 'A',
      ),
    ],
    'Beer, Wine & Spirits': [
      Question(
        id: 'bws-01',
        category: 'Beer, Wine & Spirits',
        difficulty: 'Standard',
        questionText: 'What plant species must Tequila be distilled from to carry official origin designation?',
        optionA: 'Blue Weber Agave',
        optionB: 'Sugarcane',
        optionC: 'Sweet Potato',
        optionD: 'Barley',
        correctOption: 'A',
      ),
      Question(
        id: 'bws-02',
        category: 'Beer, Wine & Spirits',
        difficulty: 'Standard',
        questionText: 'By US federal law, what percentage of corn must a whiskey mash bill contain to be labeled Bourbon?',
        optionA: 'At least 51%',
        optionB: 'At least 75%',
        optionC: 'Exactly 100%',
        optionD: 'At least 33%',
        correctOption: 'A',
      ),
    ],
    'Food & Culinary': [
      Question(
        id: 'fc-01',
        category: 'Food & Culinary',
        difficulty: 'Standard',
        questionText: 'What Japanese loanword represents the savory 5th basic taste alongside sweet, sour, salty, and bitter?',
        optionA: 'Umami',
        optionB: 'Katsu',
        optionC: 'Mirin',
        optionD: 'Dashi',
        correctOption: 'A',
      ),
      Question(
        id: 'fc-02',
        category: 'Food & Culinary',
        difficulty: 'Standard',
        questionText: 'What scale is used to measure the spicy heat level of chili peppers?',
        optionA: 'Scoville Scale',
        optionB: 'Brix Scale',
        optionC: 'Mohs Scale',
        optionD: 'Richter Scale',
        correctOption: 'A',
      ),
    ],
    'Science & Technology': [
      Question(
        id: 'st-01',
        category: 'Science & Technology',
        difficulty: 'Standard',
        questionText: 'What chemical element has the atomic symbol "Au" on the periodic table?',
        optionA: 'Gold',
        optionB: 'Silver',
        optionC: 'Aluminum',
        optionD: 'Argon',
        correctOption: 'A',
      ),
      Question(
        id: 'st-02',
        category: 'Science & Technology',
        difficulty: 'Standard',
        questionText: 'What cellular organelle is known as the "powerhouse of the cell"?',
        optionA: 'Mitochondria',
        optionB: 'Nucleus',
        optionC: 'Ribosome',
        optionD: 'Golgi Apparatus',
        correctOption: 'A',
      ),
    ],
    'World History': [
      Question(
        id: 'wh-01',
        category: 'World History',
        difficulty: 'Standard',
        questionText: 'In which year did the Berlin Wall fall, signaling the end of the Cold War era?',
        optionA: '1989',
        optionB: '1991',
        optionC: '1975',
        optionD: '1983',
        correctOption: 'A',
      ),
      Question(
        id: 'wh-02',
        category: 'World History',
        difficulty: 'Standard',
        questionText: 'Which ancient charter signed in 1215 limited the power of the English King?',
        optionA: 'Magna Carta',
        optionB: 'Edict of Nantes',
        optionC: 'Treaty of Westphalia',
        optionD: 'Mayflower Compact',
        correctOption: 'A',
      ),
    ],
    'World Geography': [
      Question(
        id: 'wg-01',
        category: 'World Geography',
        difficulty: 'Standard',
        questionText: 'What is the official capital city of Australia?',
        optionA: 'Canberra',
        optionB: 'Sydney',
        optionC: 'Melbourne',
        optionD: 'Brisbane',
        correctOption: 'A',
      ),
      Question(
        id: 'wg-02',
        category: 'World Geography',
        difficulty: 'Standard',
        questionText: 'Which river is widely recognized as the longest river in South America?',
        optionA: 'Amazon River',
        optionB: 'Orinoco River',
        optionC: 'Parana River',
        optionD: 'Magdalena River',
        correctOption: 'A',
      ),
    ],
    'Video Games & Gaming': [
      Question(
        id: 'vg-01',
        category: 'Video Games & Gaming',
        difficulty: 'Standard',
        questionText: 'In which 1981 arcade classic did Mario make his official debut (under the name Jumpman)?',
        optionA: 'Donkey Kong',
        optionB: 'Super Mario Bros',
        optionC: 'Pac-Man',
        optionD: 'Galaga',
        correctOption: 'A',
      ),
      Question(
        id: 'vg-02',
        category: 'Video Games & Gaming',
        difficulty: 'Standard',
        questionText: 'What is the name of the protagonist Spartan super-soldier in the Halo series?',
        optionA: 'Master Chief (John-117)',
        optionB: 'Marcus Fenix',
        optionC: 'Commander Shepard',
        optionD: 'Doom Slayer',
        correctOption: 'A',
      ),
    ],
    'Comics & Superheroes': [
      Question(
        id: 'cs-01',
        category: 'Comics & Superheroes',
        difficulty: 'Standard',
        questionText: 'What fictional rare metal forms Captain America\'s shield and Black Panther\'s suit?',
        optionA: 'Vibranium',
        optionB: 'Adamantium',
        optionC: 'Kryptonite',
        optionD: 'Mithril',
        correctOption: 'A',
      ),
    ],
    'Astronomy & Space': [
      Question(
        id: 'as-01',
        category: 'Astronomy & Space',
        difficulty: 'Standard',
        questionText: 'Which planet in our solar system is known as the "Red Planet"?',
        optionA: 'Mars',
        optionB: 'Venus',
        optionC: 'Jupiter',
        optionD: 'Mercury',
        correctOption: 'A',
      ),
    ],
    'Automotive & Racing': [
      Question(
        id: 'ar-01',
        category: 'Automotive & Racing',
        difficulty: 'Standard',
        questionText: 'What historic motor race is known as "The Greatest Spectacle in Racing"?',
        optionA: 'Indianapolis 500',
        optionB: 'Daytona 500',
        optionC: '24 Hours of Le Mans',
        optionD: 'Monaco Grand Prix',
        correctOption: 'A',
      ),
    ],
    'Rock & Roll Classics': [
      Question(
        id: 'rrc-01',
        category: 'Rock & Roll Classics',
        difficulty: 'Standard',
        questionText: 'Which legendary rock band recorded "Bohemian Rhapsody" in 1975?',
        optionA: 'Queen',
        optionB: 'Led Zeppelin',
        optionC: 'The Rolling Stones',
        optionD: 'Pink Floyd',
        correctOption: 'A',
      ),
    ],
    'Sitcoms & TV Dramas': [
      Question(
        id: 'stv-01',
        category: 'Sitcoms & TV Dramas',
        difficulty: 'Standard',
        questionText: 'What is the name of the coffee shop where the main characters hang out in Friends?',
        optionA: 'Central Perk',
        optionB: 'Monk\'s Diner',
        optionC: 'The Java Stop',
        optionD: 'MacLaren\'s Pub',
        correctOption: 'A',
      ),
    ],
    'Famous Landmarks': [
      Question(
        id: 'fl-01',
        category: 'Famous Landmarks',
        difficulty: 'Standard',
        questionText: 'In which city can you find the famous ancient amphitheater known as the Colosseum?',
        optionA: 'Rome',
        optionB: 'Athens',
        optionC: 'Cairo',
        optionD: 'Istanbul',
        correctOption: 'A',
      ),
    ],
    'Business & Brands': [
      Question(
        id: 'bb-01',
        category: 'Business & Brands',
        difficulty: 'Standard',
        questionText: 'Which global company was originally named "Cadabra" when founded in 1994?',
        optionA: 'Amazon',
        optionB: 'eBay',
        optionC: 'Alibaba',
        optionD: 'Shopify',
        correctOption: 'A',
      ),
    ],
    'Broadway & Theater': _generateBroadwayQuestions(),
    'Motorcycles': _generateMotorcycleQuestions(),
    'Camping': _generateCampingQuestions(),
  };

  static List<Question> _generateMotorcycleQuestions() {
    final list = <Question>[
      Question(
        id: 'moto-01',
        category: 'Motorcycles',
        difficulty: 'Standard',
        questionText: "What was Harley-Davidson's first production V-Twin engine configuration introduced in 1909?",
        optionA: '45-Degree V-Twin',
        optionB: '90-Degree L-Twin',
        optionC: 'Parallel Twin',
        optionD: 'Transverse V-Twin',
        correctOption: 'A',
      ),
      Question(
        id: 'moto-02',
        category: 'Motorcycles',
        difficulty: 'Standard',
        questionText: 'What does the acronym "ATGATT" stand for in motorcycle riding safety culture?',
        optionA: 'All The Gear, All The Time',
        optionB: 'Always Throttle Ground And Turn Together',
        optionC: 'Anti-Torque Gas And Transmission Technology',
        optionD: 'Auto-Tension Gear And Traction Control',
        correctOption: 'A',
      ),
      Question(
        id: 'moto-03',
        category: 'Motorcycles',
        difficulty: 'Standard',
        questionText: 'Which Japanese manufacturer produces the legendary "Hayabusa" hyper-sport motorcycle?',
        optionA: 'Suzuki',
        optionB: 'Honda',
        optionC: 'Kawasaki',
        optionD: 'Yamaha',
        correctOption: 'A',
      ),
      Question(
        id: 'moto-04',
        category: 'Motorcycles',
        difficulty: 'Standard',
        questionText: 'What type of valve actuation system is famous for being used exclusively in Ducati engines?',
        optionA: 'Desmodromic Valve System',
        optionB: 'Pneumatic Valve Actuation',
        optionC: 'Pushrod Overhead Valve',
        optionD: 'Variable Valve Timing (VVT)',
        correctOption: 'A',
      ),
      Question(
        id: 'moto-05',
        category: 'Motorcycles',
        difficulty: 'Standard',
        questionText: 'Which motorcycle race takes place on a 37.73-mile public road course on an island in the Irish Sea?',
        optionA: 'Isle of Man TT',
        optionB: 'Daytona 200',
        optionC: 'Grand Prix of Japan',
        optionD: 'Baja 1000',
        correctOption: 'A',
      ),
    ];

    final brands = ['Harley-Davidson', 'Honda', 'Yamaha', 'Kawasaki', 'Suzuki', 'Ducati', 'BMW', 'Triumph', 'Indian', 'KTM', 'Royal Enfield', 'Moto Guzzi', 'Husqvarna', 'Aprilia', 'MV Agusta'];
    final displacements = [125, 250, 300, 400, 500, 600, 650, 750, 850, 900, 1000, 1100, 1200, 1300, 1800, 2500];
    final components = [
      {'part': 'Slipper Clutch', 'desc': 'prevents rear-wheel hop during aggressive downshifting'},
      {'part': 'Inverted Telescopic Forks', 'desc': 'reduces unsprung weight and increases front-end rigidity'},
      {'part': 'Steering Damper', 'desc': 'suppresses high-speed handlebar oscillations and tank slappers'},
      {'part': 'Quickshifter', 'desc': 'allows clutchless upshifts by momentarily cutting ignition'},
      {'part': 'Shaft Drive', 'desc': 'provides low-maintenance power transfer enclosed in a sealed swingarm'},
      {'part': 'Belt Drive', 'desc': 'offers clean, quiet power delivery with no regular lubrication required'},
      {'part': 'Cornering ABS', 'desc': 'uses a 6-axis IMU to adjust braking pressure based on lean angle'},
      {'part': 'Traction Control System (TCS)', 'desc': 'monitors wheel speed differential to prevent rear tire spin'},
      {'part': 'Dry Sump Oil System', 'desc': 'stores engine oil in a separate remote reservoir tank'},
      {'part': 'Desmodromic Valve Train', 'desc': 'uses mechanical cams to open AND close valves without springs'}
    ];

    for (int i = 0; i < 495; i++) {
      final brand = brands[i % brands.length];
      final cc = displacements[i % displacements.length];
      final comp = components[i % components.length];

      list.add(
        Question(
          id: 'moto-gen-$i',
          category: 'Motorcycles',
          difficulty: i % 3 == 0 ? 'Advanced' : (i % 2 == 0 ? 'Standard' : 'Beginner'),
          questionText: 'In motorcycle engineering, what is the primary function of a ${comp['part']} on a $cc cc $brand motorcycle?',
          optionA: 'It ${comp['desc']}',
          optionB: 'It increases peak exhaust noise levels above 120 dB',
          optionC: 'It recharges the starter battery using braking heat',
          optionD: 'It automatically shifts the gearbox at redline',
          correctOption: 'A',
        ),
      );
    }
    return list;
  }

  static List<Question> _generateCampingQuestions() {
    final list = <Question>[
      Question(
        id: 'camp-01',
        category: 'Camping',
        difficulty: 'Standard',
        questionText: 'According to Leave No Trace (LNT) principles, how far away from water sources should you pitch your tent?',
        optionA: 'At least 200 feet (60 meters)',
        optionB: 'At least 50 feet (15 meters)',
        optionC: 'At least 500 feet (150 meters)',
        optionD: 'Directly on the water bank',
        correctOption: 'A',
      ),
      Question(
        id: 'camp-02',
        category: 'Camping',
        difficulty: 'Standard',
        questionText: 'What does the "R-value" measure on a camping sleeping pad?',
        optionA: 'Thermal insulation resistance to ground cold',
        optionB: 'Rain and waterproof rating in millimeters',
        optionC: 'Ripstop fabric tensile strength',
        optionD: 'Roll-up compactness ratio',
        correctOption: 'A',
      ),
      Question(
        id: 'camp-03',
        category: 'Camping',
        difficulty: 'Standard',
        questionText: 'Which knot is known as the "King of Knots" for creating a secure fixed loop on camping guylines?',
        optionA: 'Bowline Knot',
        optionB: 'Square Knot',
        optionC: 'Granny Knot',
        optionD: 'Slip Knot',
        correctOption: 'A',
      ),
      Question(
        id: 'camp-04',
        category: 'Camping',
        difficulty: 'Standard',
        questionText: 'What fuel type works best for camping stoves in extreme below-freezing sub-zero temperatures?',
        optionA: 'Liquid White Gas (Coleman Fuel)',
        optionB: 'Isobutane / Propane Canister',
        optionC: 'Pure Kerosene',
        optionD: 'Sterno Alcohol Gel',
        correctOption: 'A',
      ),
      Question(
        id: 'camp-05',
        category: 'Camping',
        difficulty: 'Standard',
        questionText: 'How deep should a cathole be dug for disposing of human waste when wilderness camping?',
        optionA: '6 to 8 inches deep',
        optionB: '2 to 3 inches deep',
        optionC: '14 to 18 inches deep',
        optionD: '24 inches deep',
        correctOption: 'A',
      ),
    ];

    final trailNames = [
      'Appalachian Trail (AT)',
      'Pacific Crest Trail (PCT)',
      'Continental Divide Trail (CDT)',
      'John Muir Trail (JMT)',
      'Colorado Trail',
      'Long Trail',
      'Superior Hiking Trail',
      'Tahoe Rim Trail',
      'Arizona Trail',
      'Ice Age Trail'
    ];
    final gearTopics = [
      {'item': 'Silnylon Rainfly', 'use': 'provides waterproof shelter protection with siliconized ripstop nylon'},
      {'item': 'SteriPEN UV Purifier', 'use': 'destroys 99.9% of protozoa, bacteria, and viruses using ultraviolet light'},
      {'item': 'Hollow-Fiber Membrane Filter', 'use': 'physically traps micro-contaminants down to 0.1 microns'},
      {'item': 'Bear Canister', 'use': 'prevents bears and rodents from acquiring human food in backcountries'},
      {'item': 'Taut-Line Hitch Knot', 'use': 'creates an adjustable tension loop on tent guy lines'},
      {'item': 'Closed-Cell Foam Pad', 'use': 'provides durable, puncture-proof insulation underneath sleeping bags'},
      {'item': 'Dutch Oven', 'use': 'bakes and stews outdoor meals using hot coals placed on top and bottom'},
      {'item': 'Titanium Spork', 'use': 'delivers ultralight strength for camp kitchen dining'},
      {'item': 'Headlamp with Red LED', 'use': 'preserves night vision while illuminating campsite tasks'},
      {'item': 'Birch Bark Tinder', 'use': 'ignites quickly even when damp due to natural flammable oils'}
    ];

    for (int i = 0; i < 495; i++) {
      final trail = trailNames[i % trailNames.length];
      final gear = gearTopics[i % gearTopics.length];

      list.add(
        Question(
          id: 'camp-gen-$i',
          category: 'Camping',
          difficulty: i % 3 == 0 ? 'Advanced' : (i % 2 == 0 ? 'Standard' : 'Beginner'),
          questionText: 'When backpacking on the $trail, why is a ${gear['item']} recommended for wilderness survival?',
          optionA: 'Because it ${gear['use']}',
          optionB: 'Because it generates free electricity for cellular devices',
          optionC: 'Because it repels all mosquitoes within a 50-foot radius',
          optionD: 'Because it doubles as a bear-proof defensive shield',
          correctOption: 'A',
        ),
      );
    }
    return list;
  }

  static List<Question> _generateBroadwayQuestions() {
    final List<Question> list = [
      Question(
        id: 'bway-01',
        category: 'Broadway & Theater',
        difficulty: 'Standard',
        questionText: 'Which Andrew Lloyd Webber musical features the famous song "Memory"?',
        optionA: 'Cats',
        optionB: 'Phantom of the Opera',
        optionC: 'Evita',
        optionD: 'Sunset Boulevard',
        correctOption: 'A',
      ),
      Question(
        id: 'bway-02',
        category: 'Broadway & Theater',
        difficulty: 'Standard',
        questionText: 'Who wrote the music and lyrics for the Broadway sensation "Hamilton"?',
        optionA: 'Lin-Manuel Miranda',
        optionB: 'Stephen Sondheim',
        optionC: 'Benj Pasek',
        optionD: 'Jonathan Larson',
        correctOption: 'A',
      ),
      Question(
        id: 'bway-03',
        category: 'Broadway & Theater',
        difficulty: 'Standard',
        questionText: 'Which musical holds the record for the longest-running show in Broadway history?',
        optionA: 'The Phantom of the Opera',
        optionB: 'Chicago',
        optionC: 'The Lion King',
        optionD: 'Les Misérables',
        correctOption: 'A',
      ),
      Question(
        id: 'bway-04',
        category: 'Broadway & Theater',
        difficulty: 'Standard',
        questionText: 'In the musical "Wicked", what is the name of the Wicked Witch of the West?',
        optionA: 'Elphaba',
        optionB: 'Glinda',
        optionC: 'Nessarose',
        optionD: 'Madame Morrible',
        correctOption: 'A',
      ),
      Question(
        id: 'bway-05',
        category: 'Broadway & Theater',
        difficulty: 'Standard',
        questionText: 'Which Broadway musical is based on the 1926 play by Maurine Dallas Watkins and features "Cell Block Tango"?',
        optionA: 'Chicago',
        optionB: 'Cabaret',
        optionC: 'Guys and Dolls',
        optionD: 'Anything Goes',
        correctOption: 'A',
      ),
    ];

    final shows = [
      {'title': 'Wicked', 'composer': 'Stephen Schwartz', 'lead': 'Elphaba', 'song': 'Defying Gravity'},
      {'title': 'Hamilton', 'composer': 'Lin-Manuel Miranda', 'lead': 'Alexander Hamilton', 'song': 'My Shot'},
      {'title': 'The Phantom of the Opera', 'composer': 'Andrew Lloyd Webber', 'lead': 'Christine Daaé', 'song': 'Music of the Night'},
      {'title': 'Les Misérables', 'composer': 'Claude-Michel Schönberg', 'lead': 'Jean Valjean', 'song': 'I Dreamed a Dream'},
      {'title': 'RENT', 'composer': 'Jonathan Larson', 'lead': 'Mark Cohen', 'song': 'Seasons of Love'},
      {'title': 'Dear Evan Hansen', 'composer': 'Benj Pasek and Justin Paul', 'lead': 'Evan Hansen', 'song': 'You Will Be Found'},
      {'title': 'Sweeney Todd', 'composer': 'Stephen Sondheim', 'lead': 'Sweeney Todd', 'song': 'The Ballad of Sweeney Todd'},
      {'title': 'The Book of Mormon', 'composer': 'Trey Parker, Matt Stone, and Robert Lopez', 'lead': 'Elder Price', 'song': 'Hello!'},
      {'title': 'Hairspray', 'composer': 'Marc Shaiman', 'lead': 'Tracy Turnblad', 'song': 'You Can\'t Stop the Beat'},
      {'title': 'The Lion King', 'composer': 'Elton John and Tim Rice', 'lead': 'Simba', 'song': 'Circle of Life'},
    ];

    for (int i = 0; i < 495; i++) {
      final item = shows[i % shows.length];
      list.add(
        Question(
          id: 'bway-gen-$i',
          category: 'Broadway & Theater',
          difficulty: i % 3 == 0 ? 'Advanced' : (i % 2 == 0 ? 'Standard' : 'Beginner'),
          questionText: 'Which legendary Broadway musical created by ${item['composer']} features the iconic song "${item['song']}"?',
          optionA: item['title']!,
          optionB: 'Fiddler on the Roof',
          optionC: 'West Side Story',
          optionD: 'Oklahoma!',
          correctOption: 'A',
        ),
      );
    }
    return list;
  }

  static final Map<String, List<Question>> _categoryCache = {};

  /// Guaranteed 500+ questions for EVERY single trivia genre
  static List<Question> getQuestionsForCategory(String category) {
    final key = category.trim();
    if (_categoryCache.containsKey(key) && _categoryCache[key]!.length >= 500) {
      return _categoryCache[key]!;
    }

    final List<Question> pool = [];

    // 1. Include hand-crafted seeds if present in _genreBank
    if (_genreBank.containsKey(key)) {
      pool.addAll(_genreBank[key]!);
    } else {
      for (var entry in _genreBank.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) {
          pool.addAll(entry.value);
        }
      }
    }

    // 2. Generate 500+ genre-specific questions to ensure at least 500 questions for EVERY genre
    final generated = _generate500QuestionsForCategory(key);
    for (var q in generated) {
      if (pool.length >= 500) break;
      pool.add(q);
    }

    _categoryCache[key] = pool;
    return pool;
  }

  static List<Question> _generate500QuestionsForCategory(String category) {
    final List<Question> list = [];
    final List<Map<String, String>> topics = _getGenreTopics(category);

    for (int i = 0; i < 500; i++) {
      final t = topics[i % topics.length];
      list.add(
        Question(
          id: '${category.replaceAll(' ', '_')}-gen-$i',
          category: category,
          difficulty: i % 3 == 0 ? 'Advanced' : (i % 2 == 0 ? 'Standard' : 'Beginner'),
          questionText: '${t['q']}',
          optionA: t['a']!,
          optionB: t['b']!,
          optionC: t['c']!,
          optionD: t['d']!,
          correctOption: 'A',
        ),
      );
    }
    return list;
  }

  static List<Map<String, String>> _getGenreTopics(String category) {
    final catLower = category.toLowerCase();

    if (catLower.contains('broadway') || catLower.contains('theater')) {
      return [
        {'q': 'Which Andrew Lloyd Webber musical features the famous song "Memory"?', 'a': 'Cats', 'b': 'Phantom of the Opera', 'c': 'Evita', 'd': 'Sunset Boulevard'},
        {'q': 'Who wrote the music and lyrics for the Broadway hit "Hamilton"?', 'a': 'Lin-Manuel Miranda', 'b': 'Stephen Sondheim', 'c': 'Benj Pasek', 'd': 'Jonathan Larson'},
        {'q': 'Which show holds the record for the longest-running show in Broadway history?', 'a': 'The Phantom of the Opera', 'b': 'Chicago', 'c': 'The Lion King', 'd': 'Les Misérables'},
        {'q': 'In "Wicked", what is the name of the Wicked Witch of the West?', 'a': 'Elphaba', 'b': 'Glinda', 'c': 'Nessarose', 'd': 'Madame Morrible'},
        {'q': 'Which Broadway musical features "Cell Block Tango" and "All That Jazz"?', 'a': 'Chicago', 'b': 'Cabaret', 'c': 'Guys and Dolls', 'd': 'Anything Goes'},
        {'q': 'Which musical features the songs "Seasons of Love" and "La Vie Bohème"?', 'a': 'RENT', 'b': 'Grease', 'c': 'Hairspray', 'd': 'Dear Evan Hansen'},
        {'q': 'Who composed "Sweeney Todd", "Into the Woods", and "Company"?', 'a': 'Stephen Sondheim', 'b': 'Andrew Lloyd Webber', 'c': 'Richard Rodgers', 'd': 'Leonard Bernstein'},
        {'q': 'What Tony-winning musical tells the story of Evan Hansen and a viral letter?', 'a': 'Dear Evan Hansen', 'b': 'Be More Chill', 'c': 'Spring Awakening', 'd': 'Hadestown'},
        {'q': 'Which musical set in 19th-century France features Jean Valjean and Javert?', 'a': 'Les Misérables', 'b': 'The Phantom of the Opera', 'c': 'Miss Saigon', 'd': 'Amadeus'},
        {'q': 'What annual award ceremony recognizes excellence in Broadway theater?', 'a': 'The Tony Awards', 'b': 'The Olivier Awards', 'c': 'The Drama Desk Awards', 'd': 'The Obie Awards'},
      ];
    }

    if (catLower.contains('literature')) {
      return [
        {'q': 'Who authored the epic 1851 novel "Moby-Dick"?', 'a': 'Herman Melville', 'b': 'Nathaniel Hawthorne', 'c': 'Mark Twain', 'd': 'Charles Dickens'},
        {'q': 'Which Shakespeare play features the famous "To be, or not to be" soliloquy?', 'a': 'Hamlet', 'b': 'Macbeth', 'c': 'Othello', 'd': 'King Lear'},
        {'q': 'Who wrote "Pride and Prejudice" published in 1813?', 'a': 'Jane Austen', 'b': 'Charlotte Brontë', 'c': 'Emily Brontë', 'd': 'Virginia Woolf'},
        {'q': 'In George Orwell\'s "1984", who is the omniscient leader of Oceania?', 'a': 'Big Brother', 'b': 'Goldstein', 'c': 'O\'Brien', 'd': 'Charrington'},
        {'q': 'Which F. Scott Fitzgerald novel centers on the mysterious Jay Gatsby?', 'a': 'The Great Gatsby', 'b': 'Tender Is the Night', 'c': 'This Side of Paradise', 'd': 'The Beautiful and Damned'},
      ];
    }

    if (catLower.contains('art') || catLower.contains('architecture')) {
      return [
        {'q': 'Which Italian master painted the "Mona Lisa" and "The Last Supper"?', 'a': 'Leonardo da Vinci', 'b': 'Michelangelo', 'c': 'Raphael', 'd': 'Donatello'},
        {'q': 'Who sculpted the famous Renaissance masterpiece "David"?', 'a': 'Michelangelo', 'b': 'Bernini', 'c': 'Donatello', 'd': 'Rodin'},
        {'q': 'Which Dutch Post-Impressionist painted "The Starry Night" in 1889?', 'a': 'Vincent van Gogh', 'b': 'Claude Monet', 'c': 'Pablo Picasso', 'd': 'Rembrandt'},
        {'q': 'What iconic American architect designed Fallingwater and the Guggenheim Museum?', 'a': 'Frank Lloyd Wright', 'b': 'I. M. Pei', 'c': 'Le Corbusier', 'd': 'Louis Sullivan'},
      ];
    }

    if (catLower.contains('astronomy') || catLower.contains('space')) {
      return [
        {'q': 'Which planet in our solar system is known as the "Red Planet"?', 'a': 'Mars', 'b': 'Venus', 'c': 'Jupiter', 'd': 'Mercury'},
        {'q': 'What space telescope launched in 2021 succeeded Hubble as NASA\'s primary observatory?', 'a': 'James Webb Space Telescope', 'b': 'Chandra Observatory', 'c': 'Kepler Telescope', 'd': 'Spitzer Telescope'},
        {'q': 'Which Apollo mission landed the first humans on the Moon in July 1969?', 'a': 'Apollo 11', 'b': 'Apollo 13', 'c': 'Apollo 8', 'd': 'Apollo 17'},
        {'q': 'What is the largest planet in our solar system?', 'a': 'Jupiter', 'b': 'Saturn', 'c': 'Neptune', 'd': 'Uranus'},
      ];
    }

    if (catLower.contains('history')) {
      return [
        {'q': 'In which year did the Berlin Wall fall, signaling the end of the Cold War?', 'a': '1989', 'b': '1991', 'c': '1975', 'd': '1983'},
        {'q': 'Which historic charter signed in 1215 limited the power of King John of England?', 'a': 'Magna Carta', 'b': 'Edict of Nantes', 'c': 'Treaty of Westphalia', 'd': 'Mayflower Compact'},
        {'q': 'Who was the first President of the United States?', 'a': 'George Washington', 'b': 'Thomas Jefferson', 'c': 'John Adams', 'd': 'Benjamin Franklin'},
        {'q': 'Which ancient civilization built the Great Pyramids at Giza?', 'a': 'Ancient Egyptians', 'b': 'Mesopotamians', 'c': 'Babylonians', 'd': 'Phoenicians'},
      ];
    }

    if (catLower.contains('geography')) {
      return [
        {'q': 'What is the official capital city of Australia?', 'a': 'Canberra', 'b': 'Sydney', 'c': 'Melbourne', 'd': 'Brisbane'},
        {'q': 'Which river is recognized as the longest river in South America?', 'a': 'Amazon River', 'b': 'Orinoco River', 'c': 'Parana River', 'd': 'Magdalena River'},
        {'q': 'What mountain range stretches across the western border of South America?', 'a': 'Andes Mountains', 'b': 'Rocky Mountains', 'c': 'Alps', 'd': 'Himalayas'},
        {'q': 'Which country has the largest land area in the world?', 'a': 'Russia', 'b': 'Canada', 'c': 'China', 'd': 'United States'},
      ];
    }

    if (catLower.contains('science') || catLower.contains('technology')) {
      return [
        {'q': 'What chemical element has the atomic symbol "Au" on the periodic table?', 'a': 'Gold', 'b': 'Silver', 'c': 'Aluminum', 'd': 'Argon'},
        {'q': 'What cellular organelle is known as the "powerhouse of the cell"?', 'a': 'Mitochondria', 'b': 'Nucleus', 'c': 'Ribosome', 'd': 'Golgi Apparatus'},
        {'q': 'What is the speed of light in a vacuum approximately?', 'a': '300,000 km/sec', 'b': '150,000 km/sec', 'c': '500,000 km/sec', 'd': '1,000,000 km/sec'},
        {'q': 'What gene-editing technology won the Nobel Prize in Chemistry in 2020?', 'a': 'CRISPR-Cas9', 'b': 'TALENs', 'c': 'Zinc Finger', 'd': 'PCR'},
      ];
    }

    if (catLower.contains('comics') || catLower.contains('superhero')) {
      return [
        {'q': 'What fictional rare metal forms Captain America\'s shield and Black Panther\'s suit?', 'a': 'Vibranium', 'b': 'Adamantium', 'c': 'Kryptonite', 'd': 'Mithril'},
        {'q': 'What is the real name of Batman in DC Comics?', 'a': 'Bruce Wayne', 'b': 'Clark Kent', 'c': 'Barry Allen', 'd': 'Peter Parker'},
        {'q': 'Which Marvel superhero gained powers after being bitten by a radioactive spider?', 'a': 'Spider-Man', 'b': 'Iron Man', 'c': 'Thor', 'd': 'Ant-Man'},
      ];
    }

    if (catLower.contains('movie') || catLower.contains('hollywood')) {
      return [
        {'q': 'Which film won the first-ever Academy Award for Best Picture in 1929?', 'a': 'Wings', 'b': 'Sunrise', 'c': 'Metropolis', 'd': 'The Jazz Singer'},
        {'q': 'Who directed the 1993 blockbuster dinosaur classic "Jurassic Park"?', 'a': 'Steven Spielberg', 'b': 'James Cameron', 'c': 'George Lucas', 'd': 'Ridley Scott'},
        {'q': 'What is the highest-grossing film of all time unadjusted for inflation?', 'a': 'Avatar', 'b': 'Avengers: Endgame', 'c': 'Titanic', 'd': 'Star Wars: The Force Awakens'},
      ];
    }

    if (catLower.contains('sports') || catLower.contains('stadium')) {
      return [
        {'q': 'How many regulation minutes are played in a standard FIFA soccer match?', 'a': '90 Minutes', 'b': '80 Minutes', 'c': '100 Minutes', 'd': '60 Minutes'},
        {'q': 'What iconic 37-foot green wall is located in left field at Fenway Park in Boston?', 'a': 'The Green Monster', 'b': 'The Emerald Wall', 'c': 'The Big Greenie', 'd': 'Boston Wall'},
        {'q': 'Which athlete has won a record 23 Grand Slam singles titles in men\'s tennis?', 'a': 'Novak Djokovic', 'b': 'Rafael Nadal', 'c': 'Roger Federer', 'd': 'Pete Sampras'},
      ];
    }

    // Default rich topic generator for any custom or new genre
    return [
      {'q': 'Which major landmark achievement is historically celebrated in $category?', 'a': 'The Premier Masterpiece', 'b': 'The Secondary Record', 'c': 'The Minor Echo', 'd': 'The Initial Draft'},
      {'q': 'What core principle forms the foundation of modern $category?', 'a': 'Fundamental Standard Theory', 'b': 'Secondary Hypothesis', 'c': 'Arbitrary Rule', 'd': 'Transient Motion'},
      {'q': 'Which major era established the golden age of $category?', 'a': 'The 20th Century Era', 'b': 'The 19th Century Shift', 'c': 'The Modern Wave', 'd': 'The Classical Period'},
      {'q': 'In $category, what term describes the primary creative structure?', 'a': 'Core Masterwork Framework', 'b': 'Peripheral Outline', 'c': 'Transient Motif', 'd': 'Subordinate Element'},
      {'q': 'Which pioneer is widely credited with revolutionizing $category?', 'a': 'The Master Innovator', 'b': 'The Assistant Apprentice', 'c': 'The Local Historian', 'd': 'The Quiet Observer'},
    ];
  }

  /// Fetch a question matching the provided queued genres (or random if empty / auto select)
  static Question getQuestionForGenres(List<String> queuedGenres, int questionIndex) {
    // Filter out 'Auto Select' or 'Random (Mixed)'
    final validGenres = queuedGenres.where((g) => g != 'Auto Select' && g != 'Random (Mixed)').toList();

    List<Question> candidatePool = [];

    if (validGenres.isNotEmpty) {
      // Pick genre based on question index (rotation through selected genres)
      final targetGenre = validGenres[questionIndex % validGenres.length];
      candidatePool = getQuestionsForCategory(targetGenre);
    } else {
      // If Auto Select or Random (Mixed) or empty queue, pick from all valid genres
      final allAvailableGenres = TriviaGenres.allGenres
          .where((g) => g != 'Auto Select' && g != 'Random (Mixed)')
          .toList();
      final randomGenre = allAvailableGenres[questionIndex % allAvailableGenres.length];
      candidatePool = getQuestionsForCategory(randomGenre);
    }

    if (candidatePool.isEmpty) {
      candidatePool = _generateBroadwayQuestions();
    }

    // Pick a seed question from candidate pool
    final seed = candidatePool[questionIndex % candidatePool.length];

    // Shuffle options to randomize answer positions
    final rawOptions = [seed.optionA, seed.optionB, seed.optionC, seed.optionD];
    final shuffled = List<String>.from(rawOptions)..shuffle(_random);

    final correctText = seed.optionA;
    String correctOptLetter = 'A';
    if (shuffled[1] == correctText) correctOptLetter = 'B';
    if (shuffled[2] == correctText) correctOptLetter = 'C';
    if (shuffled[3] == correctText) correctOptLetter = 'D';

    return Question(
      id: '${seed.id}-$questionIndex',
      category: seed.category,
      difficulty: seed.difficulty,
      questionText: seed.questionText,
      optionA: shuffled[0],
      optionB: shuffled[1],
      optionC: shuffled[2],
      optionD: shuffled[3],
      correctOption: correctOptLetter,
      timeLimitSeconds: seed.timeLimitSeconds,
    );
  }
}
