-- Bar Room Trivia Seed Questions
-- Run this in Supabase SQL Editor to populate initial trivia questions bank.

INSERT INTO public.questions (category, difficulty, question_text, option_a, option_b, option_c, option_d, correct_option, time_limit_seconds) VALUES
('Beer, Wine & Spirits', 'medium', 'In homebrewing, what process converts starches from malted grain into fermentable sugars using warm water?', 'Boiling', 'Mashing', 'Fermenting', 'Sparging', 'B', 20),
('Beer, Wine & Spirits', 'easy', 'Which essential homebrewing ingredient provides bitterness, floral aromas, and natural preservative qualities?', 'Yeast', 'Hops', 'Wheat', 'Flaked Oats', 'B', 20),
('Beer, Wine & Spirits', 'medium', 'What does the abbreviation "IBU" stand for in beer brewing?', 'International Brewing Union', 'International Bitterness Units', 'Initial Boiling Utility', 'Internal Barrel Uniformity', 'B', 20),
('Beer, Wine & Spirits', 'hard', 'Which famous noble hop variety from the Czech Republic is famous for imparting spicy, herbal flavors in classic Pilsners?', 'Citra', 'Saaz', 'Mosaic', 'Amarillo', 'B', 20),
('Beer, Wine & Spirits', 'medium', 'What sanitizer chemical solution is famously no-rinse and widely used by homebrewers to sterilize equipment?', 'Bleach', 'Star San', 'Vinegar', 'Ammonia', 'B', 20),

('Pop Culture & Music', 'easy', 'Which pop icon released the hit album "Thriller" in 1982?', 'Prince', 'Michael Jackson', 'George Michael', 'Madonna', 'B', 20),
('Pop Culture & Music', 'medium', 'What band was Freddie Mercury the lead singer of?', 'The Beatles', 'Queen', 'Led Zeppelin', 'The Who', 'B', 20),
('Pop Culture & Music', 'medium', 'Which song features the lyrics "Is this the real life? Is this just fantasy?"', 'Stairway to Heaven', 'Bohemian Rhapsody', 'Hotel California', 'Sweet Child O Mine', 'B', 20),

('Movies & Hollywood', 'easy', 'Which actor played Tony Stark / Iron Man in the Marvel Cinematic Universe?', 'Chris Evans', 'Robert Downey Jr.', 'Chris Hemsworth', 'Mark Ruffalo', 'B', 20),
('Movies & Hollywood', 'medium', 'What movie won the Academy Award for Best Picture in 1994, beating Pulp Fiction and The Shawshank Redemption?', 'Titanic', 'Forrest Gump', 'Braveheart', 'Gladiator', 'B', 20),
('Movies & Hollywood', 'hard', 'In Quentin Tarantino''s "Pulp Fiction", what is a Quarter Pounder with Cheese called in Paris?', 'Royale with Cheese', 'Big Mac Deluxe', 'Le Cheeseburger', 'Quarter Franc', 'A', 20),

('Science & Technology', 'easy', 'What element has the chemical symbol "O"?', 'Gold', 'Oxygen', 'Osmium', 'Silver', 'B', 20),
('Science & Technology', 'medium', 'Which planet in our solar system is known as the Red Planet?', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'B', 20),
('Science & Technology', 'medium', 'What is the speed of light in a vacuum approximately?', '300,000 km/s', '150,000 km/s', '1,000,000 km/s', '500,000 km/s', 'A', 20),

('World History', 'medium', 'In what year did the Titanic sink on its maiden voyage?', '1905', '1912', '1918', '1923', 'B', 20),
('World History', 'easy', 'Who was the first President of the United States?', 'Thomas Jefferson', 'George Washington', 'John Adams', 'Abraham Lincoln', 'B', 20),
('World History', 'hard', 'Which empire was ruled by Julius Caesar and Augustus?', 'Greco-Bactrian Empire', 'Roman Empire', 'Ottoman Empire', 'Byzantine Empire', 'B', 20),

('World Geography', 'easy', 'What is the capital city of France?', 'London', 'Paris', 'Berlin', 'Rome', 'B', 20),
('World Geography', 'medium', 'Which is the largest ocean on Earth?', 'Atlantic Ocean', 'Pacific Ocean', 'Indian Ocean', 'Arctic Ocean', 'B', 20),
('World Geography', 'hard', 'What is the smallest independent country in the world by land area?', 'Monaco', 'Vatican City', 'San Marino', 'Liechtenstein', 'B', 20),

('Sports & Stadiums', 'easy', 'How many players are on the field for one team during a regulation soccer match?', '9', '11', '10', '12', 'B', 20),
('Sports & Stadiums', 'medium', 'Which country hosted the 2016 Summer Olympic Games?', 'United Kingdom', 'Brazil', 'China', 'Japan', 'B', 20),
('Sports & Stadiums', 'hard', 'In baseball, what is the distance in feet between the pitcher''s rubber and home plate?', '60 feet 6 inches', '55 feet', '65 feet', '70 feet', 'A', 20),

('Food & Culinary', 'easy', 'What primary ingredient is used to make guacamole?', 'Tomato', 'Avocado', 'Chickpeas', 'Eggplant', 'B', 20),
('Food & Culinary', 'medium', 'Which Italian cheese is traditionally made from water buffalo milk?', 'Parmigiano-Reggiano', 'Mozzarella di Bufala', 'Gorgonzola', 'Pecorino Romano', 'B', 20),
('Video Games & Gaming', 'easy', 'What is the name of Mario''s green dinosaur companion in Nintendo games?', 'Yoshi', 'Bowser', 'Toad', 'Luigi', 'A', 20),
('80s & 90s Nostalgia', 'medium', 'What retro portable video game console was released by Nintendo in 1989?', 'Sega Game Gear', 'Game Boy', 'Atari Lynx', 'Neo Geo Pocket', 'B', 20);
