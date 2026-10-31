/**
 * Automated Homebrewing Trivia Generation Module (Zero AI Credits / 100% Free)
 * 
 * Generates natural, human-sounding homebrewing trivia batches (25-50 questions)
 * with varied conversational stems, authentic brewing scenarios, and plausible
 * domain-matched distractors.
 * 
 * Supports deterministic weekly rotation based on calendar week or custom batch seeds.
 */

const crypto = require('crypto');

function computeHash(str) {
  const norm = (str || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return crypto.createHash('sha256').update(norm).digest('hex');
}

function shuffle(arr) {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function pickDistractors(pool, correct, count = 3) {
  const normCorrect = correct.toLowerCase().trim();
  const available = pool.filter(item => item.toLowerCase().trim() !== normCorrect);
  const shuffled = shuffle(available);
  return shuffled.slice(0, count);
}

// 1. Rich Authentic Brewing Knowledge Pools
const HOP_DATA = [
  { name: 'Citra', flavor: 'tropical mango, guava, and bright citrus', origin: 'USA', alpha: '11-13% Alpha Acids', usage: 'Aroma & Whirlpool' },
  { name: 'Mosaic', flavor: 'complex blueberry, ripe papaya, and rose floral notes', origin: 'USA', alpha: '11.5-13.5% Alpha Acids', usage: 'Dual-Purpose' },
  { name: 'Simcoe', flavor: 'earthy pine needles, passionfruit, and stone fruit', origin: 'USA', alpha: '12-14% Alpha Acids', usage: 'Dual-Purpose' },
  { name: 'Galaxy', flavor: 'candied peach, passionfruit, and clean citrus', origin: 'Australia', alpha: '13.5-15% Alpha Acids', usage: 'Aroma & Dry-Hop' },
  { name: 'Nelson Sauvin', flavor: 'crushed gooseberry and white Sauvignon Blanc wine grapes', origin: 'New Zealand', alpha: '12-13% Alpha Acids', usage: 'Aroma & Dry-Hop' },
  { name: 'Cascade', flavor: 'classic floral grapefruit zest and subtle pine', origin: 'USA', alpha: '5.5-7.5% Alpha Acids', usage: 'Aroma' },
  { name: 'Centennial', flavor: 'punchy lemon zest and clean floral aroma ("Super Cascade")', origin: 'USA', alpha: '9.5-11.5% Alpha Acids', usage: 'Dual-Purpose' },
  { name: 'Amarillo', flavor: 'sweet orange marmalade and floral blossoms', origin: 'USA', alpha: '8-11% Alpha Acids', usage: 'Aroma' },
  { name: 'Saaz', flavor: 'delicate spicy, herbal, and earthy noble character', origin: 'Czech Republic', alpha: '3-4.5% Alpha Acids', usage: 'Noble Aroma' },
  { name: 'Hallertau Mittelfrüh', flavor: 'soft herbal tea, mild spice, and noble floral aroma', origin: 'Germany', alpha: '3.5-5.5% Alpha Acids', usage: 'Noble Aroma' },
  { name: 'Fuggle', flavor: 'mild cedarwood, green tea, and earthy British character', origin: 'United Kingdom', alpha: '4-5.5% Alpha Acids', usage: 'Aroma' },
  { name: 'East Kent Goldings', flavor: 'lavender, honey, and subtle autumn spice', origin: 'United Kingdom', alpha: '4.5-6.5% Alpha Acids', usage: 'Noble Aroma' },
  { name: 'Sabro', flavor: 'creamy coconut cream, pineapple, and cedar', origin: 'USA', alpha: '12-16% Alpha Acids', usage: 'Aroma & Dry-Hop' },
  { name: 'Strata', flavor: 'fresh strawberry, passionfruit, and herbal dankness', origin: 'USA', alpha: '11-13% Alpha Acids', usage: 'Dual-Purpose' },
  { name: 'Motueka', flavor: 'fresh crushed lime zest and sweet tropical lemon', origin: 'New Zealand', alpha: '6.5-7.5% Alpha Acids', usage: 'Aroma' },
  { name: 'Magnum', flavor: 'clean, neutral, smooth high-alpha bittering', origin: 'Germany', alpha: '12-14% Alpha Acids', usage: 'Bittering' },
  { name: 'Columbus (CTZ)', flavor: 'pungent dankness, resinous pine, and dark black pepper', origin: 'USA', alpha: '14-16% Alpha Acids', usage: 'Bittering & Dry-Hop' },
  { name: 'Chinook', flavor: 'grapefruit pith, heavy pine resin, and smoky spice', origin: 'USA', alpha: '12-14% Alpha Acids', usage: 'Bittering & Aroma' },
  { name: 'El Dorado', flavor: 'ripe watermelon candy, pear, and stone fruit', origin: 'USA', alpha: '14-16% Alpha Acids', usage: 'Dual-Purpose' },
  { name: 'Vic Secret', flavor: 'clean pineapple, pine resin, and tropical fruit', origin: 'Australia', alpha: '14-17% Alpha Acids', usage: 'Aroma & Dry-Hop' },
];

const MALT_DATA = [
  { name: 'Pilsner Malt', role: 'clean, sweet, cracker-like base with very pale color', srm: '1.5 - 2 SRM', type: 'Base Malt' },
  { name: 'Maris Otter', role: 'rich, nutty, biscuit depth prized for English ales', srm: '2.5 - 3.5 SRM', type: 'Base Malt' },
  { name: 'Munich Malt', role: 'toasty bread crust, deep amber color, and rich maltiness', srm: '8 - 15 SRM', type: 'Base / Specialty' },
  { name: 'Vienna Malt', role: 'subtle toasted grain and warm golden-orange hue', srm: '3.5 - 5 SRM', type: 'Base / Specialty' },
  { name: 'Crystal / Caramel 60L', role: 'sweet toffee, caramel body, and copper red color', srm: '60 SRM', type: 'Caramel / Crystal' },
  { name: 'Crystal 120L', role: 'dark raisin, prune, and burnt sugar complexity', srm: '120 SRM', type: 'Caramel / Crystal' },
  { name: 'Chocolate Malt', role: 'dark cocoa, roasted nuts, and rich brown color without harsh acrid bitterness', srm: '350 - 450 SRM', type: 'Roasted Malt' },
  { name: 'Black Patent Malt', role: 'intense charcoal, espresso, and opaque black astringency', srm: '500+ SRM', type: 'Roasted Malt' },
  { name: 'Roasted Barley', role: 'unmalted roasted grain that produces the signature dry coffee bite and creamy tan head of Irish stouts', srm: '300 - 500 SRM', type: 'Roasted Grain' },
  { name: 'Flaked Oats', role: 'unmalted cereal grain that enhances silky, pillowy mouthfeel and head retention in NEIPAs and stouts', srm: '1 SRM', type: 'Adjunct' },
  { name: 'Flaked Wheat', role: 'raw cereal adding soft cloudiness, stable foam, and delicate bready notes to Belgian Witbiers', srm: '1.5 SRM', type: 'Adjunct' },
  { name: 'Acidulated Malt', role: 'malted barley sprayed with natural lactic acid used to gently lower mash pH without liquid chemicals', srm: '2 - 3 SRM', type: 'Specialty Malt' },
  { name: 'Smoked Beechwood Malt', role: 'hardwood-smoked grain that imparts savory campfire and smoked bacon aroma to German Rauchbiers', srm: '2 - 4 SRM', type: 'Specialty Malt' },
  { name: 'Carapils (Dextrine)', role: 'dextrin-rich malt that boosts body and foam retention without altering color or flavor', srm: '1.5 SRM', type: 'Specialty Malt' },
];

const YEAST_DATA = [
  { name: 'US-05 / California Ale', profile: 'clean, neutral, and low-ester, letting hops and malt shine without yeast fruitiness', temp: '59°F - 72°F' },
  { name: 'S-04 / English Ale', profile: 'fruity esters with rapid flocculation that settles into a rock-solid yeast cake', temp: '59°F - 68°F' },
  { name: 'WLP300 / Hefeweizen Ale', profile: 'distinctive banana (isoamyl acetate) and clove (4-vinyl guaiacol) yeast esters', temp: '68°F - 74°F' },
  { name: 'W-34/70 Weihenstephan Lager', profile: 'exceptionally clean, sulfur-free, crisp lager character even at slightly elevated temperatures', temp: '48°F - 59°F' },
  { name: 'Voss Kveik Farmhouse', profile: 'clean citrus and orange-peel esters during ultra-fast fermentation up to 98°F (37°C)', temp: '77°F - 98°F' },
  { name: 'London Ale III (Wyeast 1318)', profile: 'subtle orchard fruitiness with low attenuation that leaves pillowy residual body in hazy IPAs', temp: '64°F - 74°F' },
  { name: 'French Saison Yeast', profile: 'attenuates down to 1.000 with a peppery, spicy, bone-dry rustic farmhouse finish', temp: '68°F - 90°F' },
  { name: 'Brettanomyces bruxellensis', profile: 'slowly develops complex barnyard, pineapple, leather, and rustic funk over months of aging', temp: '65°F - 85°F' },
];

const BREW_SCIENCE = [
  {
    q: 'If your hydrometer reads an original gravity (OG) of 1.056 and finishes at 1.010, what is the approximate ABV of the beer?',
    correct: 'Approx. 6.0% ABV (calculated using (OG - FG) * 131.25)',
    wrongs: ['Approx. 3.2% ABV', 'Approx. 8.8% ABV', 'Approx. 11.5% ABV'],
    diff: 'medium'
  },
  {
    q: 'Why do homebrewers perform a "whirlpool hop stand" below 180°F (82°C) instead of boiling?',
    correct: 'To extract volatile aromatic essential oils while preventing further alpha acid isomerization into bitterness',
    wrongs: [
      'To freeze the wort before pumping it into the fermenter',
      'To kill off wild yeast cells that live on the kettle lid',
      'To convert residual malt starches into unfermentable dextrins'
    ],
    diff: 'medium'
  },
  {
    q: 'A competition judge detects unmistakable notes of movie-theater butter or butterscotch in your pilsner. Which compound caused this off-flavor?',
    correct: 'Diacetyl (caused by premature yeast separation or lack of a diacetyl rest)',
    wrongs: [
      'Dimethyl Sulfide / DMS (caused by a weak boil)',
      'Acetaldehyde (caused by green apple oxidation)',
      'Isovaleric acid (caused by old cheesy hops)'
    ],
    diff: 'easy'
  },
  {
    q: 'Your freshly opened homebrew gives off the aroma of green apples and fresh-cut pumpkin. What brewing flaw does this indicate?',
    correct: 'Acetaldehyde (fermentation was ended prematurely or the beer was bottled too young)',
    wrongs: [
      'Lightstruck skunking from clear glass bottles',
      'Excessive kettle fining additions of Irish Moss',
      'High mash temperatures producing excess dextrins'
    ],
    diff: 'easy'
  },
  {
    q: 'During the mash, what is the enzymatic difference between resting at 148°F (64°C) versus resting at 156°F (69°C)?',
    correct: '148°F favors beta-amylase for a highly fermentable, dry wort; 156°F favors alpha-amylase for fuller body and dextrins',
    wrongs: [
      '148°F destroys all enzymes immediately; 156°F converts protein into hop oils',
      '148°F creates an intensely sweet, syrupy wort; 156°F causes wort to turn sour',
      'Both temperatures produce the exact same sugar spectrum regardless of grain bill'
    ],
    diff: 'hard'
  },
  {
    q: 'In brewing water chemistry, how does adjusting the sulfate-to-chloride ratio affect beer taste?',
    correct: 'Higher sulfate sharpens crisp hop bitterness; higher chloride rounds out malt sweetness and fullness',
    wrongs: [
      'Higher sulfate adds heavy roasted cocoa flavors; higher chloride turns the beer clear',
      'Higher sulfate eliminates alcohol; higher chloride triples carbonation speed',
      'Neither mineral has any detectable impact on perceived beer flavor or mouthfeel'
    ],
    diff: 'hard'
  },
  {
    q: 'What is the optimal room-temperature mash pH range for maximum enzymatic starch conversion and tannin suppression?',
    correct: '5.2 to 5.6 pH',
    wrongs: ['3.0 to 3.5 pH', '6.8 to 7.4 pH', '8.0 to 8.5 pH'],
    diff: 'medium'
  },
  {
    q: 'When rinsing the grain bed during all-grain lautering, why should sparge water never exceed 170°F (77°C)?',
    correct: 'Water above 170°F leaches harsh, astringent polyphenol tannins from the grain husks',
    wrongs: [
      'It causes the grain starch to ferment inside the mash tun',
      'It cracks the stainless steel or plastic cooler mash tun',
      'It denatures all sugars into unfermentable cellulose'
    ],
    diff: 'medium'
  },
  {
    q: 'Why must brewers boil pilsner malt wort vigorously with the kettle lid OFF for at least 60 to 90 minutes?',
    correct: 'To volatilize and drive off SMM precursors that would otherwise turn into cooked-corn DMS (Dimethyl Sulfide)',
    wrongs: [
      'To prevent the boil kettle from exploding due to steam buildup',
      'To evaporate all alcohol produced during mashing',
      'To caramelize 100% of the light grain into dark crystal sugars'
    ],
    diff: 'hard'
  },
  {
    q: 'What causes the "lightstruck" or skunky off-flavor in beer bottled in green or clear glass?',
    correct: 'Ultraviolet and blue light breaking down isomerized hop isohumulones into 3-MBT (3-methyl-2-butene-1-thiol)',
    wrongs: [
      'Sunlight activating dormant wild yeast cells to ferment bottle caps',
      'Heat from sunlight melting the crown liner into the liquid',
      'Oxygen dissolving through the glass wall under sunlight exposure'
    ],
    diff: 'medium'
  },
  {
    q: 'When bottle conditioning with priming sugar, what is the primary benefit of table sugar (sucrose) over corn sugar (dextrose)?',
    correct: 'Sucrose is 100% fermentable by weight, whereas dextrose monohydrate contains roughly 9% water content',
    wrongs: [
      'Table sugar adds a rich dark molasses flavor to the beer',
      'Corn sugar stops yeast from producing carbon dioxide',
      'Table sugar carbonates bottles in under 15 minutes'
    ],
    diff: 'medium'
  },
  {
    q: 'What is "hop creep" when dry-hopping finished beer in the cellar or keg?',
    correct: 'Enzymes on raw hops breaking down unfermentable dextrins into fermentable sugars, restarting fermentation',
    wrongs: [
      'Hop pellets floating up to the airlock and blocking CO2 release',
      'Hop oils turning cloudy when chilled below freezing',
      'Bitterness increasing by 50 IBUs in the cold keg'
    ],
    diff: 'hard'
  },
  {
    q: 'Why is it critical to aerate or oxygenate cooled wort before pitching yeast, but strictly avoid oxygen after fermentation begins?',
    correct: 'Yeast requires oxygen early to synthesize sterols for healthy cell walls, while post-fermentation oxygen causes stale cardboard oxidation',
    wrongs: [
      'Oxygen early makes the beer sweet, while late oxygen eliminates alcohol',
      'Yeast can only ferment in pure oxygen environments throughout the entire brew',
      'Aerating cold wort prevents hop alpha acids from settling'
    ],
    diff: 'medium'
  },
  {
    q: 'In all-grain brewing, what is the purpose of the "vorlauf" step before sending wort to the boil kettle?',
    correct: 'Recirculating initial cloudy runoff through the grain bed until it sets as a natural filter for clear wort',
    wrongs: [
      'Heating the grain bed to boiling temperature to sterilize it',
      'Extracting bitter hop oils before the boil begins',
      'Adding calcium chloride directly into the dry husks'
    ],
    diff: 'easy'
  },
  {
    q: 'What is the purpose of adding finings like Irish Moss or Whirlfloc 10–15 minutes before flameout?',
    correct: 'Negatively charged carrageenan binds with positively charged proteins to form a heavy hot break that drops out of solution',
    wrongs: [
      'To add subtle herbal and oceanic flavor to Belgian ales',
      'To convert grain starches into fermentable sugars',
      'To sanitize the kettle walls against wild bacteria'
    ],
    diff: 'easy'
  }
];

// Conversational Question Stem Generators
const HOP_SCENARIO_TEMPLATES = [
  (h) => `You're formulating a juicy Pale Ale recipe and want prominent ${h.flavor}—which hop variety belongs in your whirlpool?`,
  (h) => `A homebrewer crunches fresh hop cones between their palms and detects notes of ${h.flavor}. Which hop is it?`,
  (h) => `If you pick up a foil pack of "${h.name}" hops, what country did this cultivar originally come from?`,
  (h) => `When building a brew-day schedule, how is the popular "${h.name}" hop variety typically classified?`,
  (h) => `Tasting a single-hop IPA brewed exclusively with "${h.name}" hops, which flavor profile will dominate the palate?`,
  (h) => `What typical alpha acid bittering range can a brewer expect when calculating additions of "${h.name}" hops?`,
];

const MALT_SCENARIO_TEMPLATES = [
  (m) => `A homebrewer adds "${m.name}" to the mash tun—what primary contribution does this grain make to the beer?`,
  (m) => `If a recipe designer needs ${m.role}, which grain should they measure into the grist?`,
  (m) => `Where does "${m.name}" fall on the Lovibond / SRM color scale?`,
  (m) => `When evaluating a homebrew grain bill, what category does "${m.name}" belong to?`,
];

const YEAST_SCENARIO_TEMPLATES = [
  (y) => `A brewer pitches "${y.name}" into chilled wort—what fermentation profile can they expect in the finished beer?`,
  (y) => `If you want ${y.profile}, which yeast pitch should you choose for your fermenter?`,
  (y) => `What is the ideal fermentation temperature range recommended for "${y.name}"?`,
];

/**
 * Generate a deterministic or randomized batch of natural homebrewing questions
 * @param {Object} options
 * @param {number} options.count - Number of questions to return (default: 25)
 * @param {number|string} options.seed - Optional seed or week index for rotation
 */
function generateNaturalHomebrewBatch(options = {}) {
  const count = options.count || 25;
  const pool = [];
  const seenHashes = new Set();

  function addQuestion(qText, correct, optB, optC, optD, diff = 'medium') {
    const hash = computeHash(qText);
    if (seenHashes.has(hash)) return;
    seenHashes.add(hash);

    const rawOpts = [
      { text: correct, isCorrect: true },
      { text: optB, isCorrect: false },
      { text: optC, isCorrect: false },
      { text: optD, isCorrect: false }
    ];
    const shuffledOpts = shuffle(rawOpts);
    const letters = ['A', 'B', 'C', 'D'];
    const correctIdx = shuffledOpts.findIndex(o => o.isCorrect);

    pool.push({
      id: `hb_nat_${pool.length + 1}_${hash.slice(0, 8)}`,
      category: 'Homebrewing Beer',
      difficulty: diff,
      question_text: qText,
      option_a: shuffledOpts[0].text,
      option_b: shuffledOpts[1].text,
      option_c: shuffledOpts[2].text,
      option_d: shuffledOpts[3].text,
      correct_option: letters[correctIdx],
      time_limit_seconds: 20
    });
  }

  // 1. Add brewing science questions
  const shuffledScience = shuffle(BREW_SCIENCE);
  for (const s of shuffledScience) {
    addQuestion(s.q, s.correct, s.wrongs[0], s.wrongs[1], s.wrongs[2], s.diff);
  }

  // 2. Add hop scenario questions
  const allHopNames = HOP_DATA.map(h => h.name);
  const allHopFlavors = HOP_DATA.map(h => h.flavor);
  const allHopOrigins = [...new Set(HOP_DATA.map(h => h.origin))];
  const allHopAlphas = [...new Set(HOP_DATA.map(h => h.alpha))];
  const allHopUsages = ['Aroma & Whirlpool', 'Bittering', 'Dual-Purpose', 'Noble Aroma', 'Late Addition'];

  const shuffledHops = shuffle(HOP_DATA);
  for (let i = 0; i < shuffledHops.length; i++) {
    const h = shuffledHops[i];
    const flavorD = pickDistractors(allHopFlavors, h.flavor, 3);
    const nameD = pickDistractors(allHopNames, h.name, 3);
    const origD = pickDistractors(allHopOrigins, h.origin, 3);
    const alphaD = pickDistractors(allHopAlphas, h.alpha, 3);
    const usageD = pickDistractors(allHopUsages, h.usage, 3);

    // Prompt 1: Flavor in recipe
    addQuestion(
      HOP_SCENARIO_TEMPLATES[0](h),
      h.name,
      nameD[0],
      nameD[1],
      nameD[2],
      'medium'
    );

    // Prompt 2: Palate sensory profile
    addQuestion(
      HOP_SCENARIO_TEMPLATES[4](h),
      `Prominent ${h.flavor}`,
      `Prominent ${flavorD[0]}`,
      `Prominent ${flavorD[1]}`,
      `Prominent ${flavorD[2]}`,
      'easy'
    );

    // Prompt 3: Origin
    addQuestion(
      HOP_SCENARIO_TEMPLATES[2](h),
      h.origin,
      origD[0],
      origD[1],
      origD[2],
      'easy'
    );

    // Prompt 4: Alpha acids
    addQuestion(
      HOP_SCENARIO_TEMPLATES[5](h),
      h.alpha,
      alphaD[0],
      alphaD[1],
      alphaD[2],
      'hard'
    );
  }

  // 3. Add malt scenario questions
  const allMaltNames = MALT_DATA.map(m => m.name);
  const allMaltRoles = MALT_DATA.map(m => m.role);
  const allMaltSrms = [...new Set(MALT_DATA.map(m => m.srm))];
  const allMaltTypes = ['Base Malt', 'Caramel / Crystal', 'Roasted Malt', 'Roasted Grain', 'Specialty Malt', 'Adjunct'];

  const shuffledMalts = shuffle(MALT_DATA);
  for (let i = 0; i < shuffledMalts.length; i++) {
    const m = shuffledMalts[i];
    const roleD = pickDistractors(allMaltRoles, m.role, 3);
    const nameD = pickDistractors(allMaltNames, m.name, 3);
    const srmD = pickDistractors(allMaltSrms, m.srm, 3);
    const typeD = pickDistractors(allMaltTypes, m.type, 3);

    // Prompt 1: What does grain contribute
    addQuestion(
      MALT_SCENARIO_TEMPLATES[0](m),
      m.role,
      roleD[0],
      roleD[1],
      roleD[2],
      'medium'
    );

    // Prompt 2: Which grain for this role
    addQuestion(
      MALT_SCENARIO_TEMPLATES[1](m),
      m.name,
      nameD[0],
      nameD[1],
      nameD[2],
      'medium'
    );

    // Prompt 3: SRM color
    addQuestion(
      MALT_SCENARIO_TEMPLATES[2](m),
      m.srm,
      srmD[0],
      srmD[1],
      srmD[2],
      'hard'
    );

    // Prompt 4: Category
    addQuestion(
      MALT_SCENARIO_TEMPLATES[3](m),
      m.type,
      typeD[0],
      typeD[1],
      typeD[2],
      'easy'
    );
  }

  // 4. Add yeast scenario questions
  const allYeastNames = YEAST_DATA.map(y => y.name);
  const allYeastProfiles = YEAST_DATA.map(y => y.profile);
  const allYeastTemps = [...new Set(YEAST_DATA.map(y => y.temp))];

  const shuffledYeast = shuffle(YEAST_DATA);
  for (let i = 0; i < shuffledYeast.length; i++) {
    const y = shuffledYeast[i];
    const profD = pickDistractors(allYeastProfiles, y.profile, 3);
    const nameD = pickDistractors(allYeastNames, y.name, 3);
    const tempD = pickDistractors(allYeastTemps, y.temp, 3);

    addQuestion(
      YEAST_SCENARIO_TEMPLATES[0](y),
      y.profile,
      profD[0],
      profD[1],
      profD[2],
      'medium'
    );

    addQuestion(
      YEAST_SCENARIO_TEMPLATES[1](y),
      y.name,
      nameD[0],
      nameD[1],
      nameD[2],
      'medium'
    );

    addQuestion(
      YEAST_SCENARIO_TEMPLATES[2](y),
      y.temp,
      tempD[0],
      tempD[1],
      tempD[2],
      'hard'
    );
  }

  const finalPool = shuffle(pool);
  return finalPool.slice(0, count);
}

module.exports = {
  generateNaturalHomebrewBatch
};
