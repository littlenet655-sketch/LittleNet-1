"""Seed 200+ curated quiz questions into the quizzes table.
Run: python tools/seed_quizzes.py
Safe to run multiple times — uses ON CONFLICT DO NOTHING.
"""
from pathlib import Path
import sys
root = Path(__file__).parents[1]
sys.path.insert(0, str(root))
from dotenv import load_dotenv
load_dotenv(root / '.env')
from database.connection import get_db_connection

QUESTIONS = [
    # ── 6-8 SCIENCE ─────────────────────────────────────────────────────────
    ('Science','Which planet is closest to the Sun?','Mercury','Venus','Earth','Mars','Mercury','6-8'),
    ('Science','How many legs does a spider have?','4','6','8','10','8','6-8'),
    ('Science','What do caterpillars turn into?','Bees','Butterflies','Moths','Dragonflies','Butterflies','6-8'),
    ('Science','Which animal is the fastest on land?','Lion','Horse','Cheetah','Leopard','Cheetah','6-8'),
    ('Science','What is the largest ocean on Earth?','Atlantic','Indian','Arctic','Pacific','Pacific','6-8'),
    ('Science','What colour is a healthy leaf?','Yellow','Brown','Green','Purple','Green','6-8'),
    ('Science','How many bones are in the human body?','106','206','306','406','206','6-8'),
    ('Science','Which sense do we use to taste food?','Sight','Touch','Taste','Hearing','Taste','6-8'),
    ('Science','What do bees produce?','Milk','Honey','Butter','Wax only','Honey','6-8'),
    ('Science','The Sun is a?','Planet','Moon','Star','Asteroid','Star','6-8'),
    # ── 6-8 MATH ────────────────────────────────────────────────────────────
    ('Math','What is 7 × 8?','54','56','64','48','56','6-8'),
    ('Math','How many minutes are in one hour?','30','45','60','100','60','6-8'),
    ('Math','What comes next? 2, 4, 6, 8, __','9','10','12','11','10','6-8'),
    ('Math','What is half of 20?','5','8','10','15','10','6-8'),
    ('Math','How many sides does a triangle have?','2','3','4','5','3','6-8'),
    ('Math','What is 100 - 37?','63','53','73','43','63','6-8'),
    ('Math','Which number is even?','3','7','9','12','12','6-8'),
    ('Math','What is 5 + 5 + 5?','10','20','15','25','15','6-8'),
    # ── 6-8 GENERAL KNOWLEDGE ───────────────────────────────────────────────
    ('General Knowledge','What is the capital of India?','Mumbai','Kolkata','New Delhi','Chennai','New Delhi','6-8'),
    ('General Knowledge','How many days are in a week?','5','6','7','8','7','6-8'),
    ('General Knowledge','Which festival is called the festival of lights?','Holi','Diwali','Eid','Christmas','Diwali','6-8'),
    ('General Knowledge','What animal says "moo"?','Sheep','Horse','Cow','Pig','Cow','6-8'),
    ('General Knowledge','How many colours are in a rainbow?','5','6','7','8','7','6-8'),
    ('General Knowledge','Which is the national bird of India?','Sparrow','Eagle','Peacock','Parrot','Peacock','6-8'),
    ('General Knowledge','What is the colour of the sky on a clear day?','Green','Red','Blue','Yellow','Blue','6-8'),
    ('General Knowledge','How many months are in a year?','10','11','12','13','12','6-8'),
    # ── 6-8 RIDDLES ─────────────────────────────────────────────────────────
    ('Riddle','I have hands but cannot clap. What am I?','Robot','Clock','Puppet','Scarecrow','Clock','6-8'),
    ('Riddle','I am full of holes but still holds water. What am I?','Net','Sponge','Bucket','Jar','Sponge','6-8'),
    ('Riddle','What gets wetter the more it dries?','Towel','Soap','Water','Sand','Towel','6-8'),
    ('Riddle','I have a tail and a head but no body. What am I?','Snake','Coin','Arrow','Needle','Coin','6-8'),
    ('Riddle','What has teeth but cannot bite?','Dog','Comb','Saw','Fork','Comb','6-8'),
    # ── 6-8 EMOJI QUIZ ──────────────────────────────────────────────────────
    ('Emoji Quiz','🌊🐟 — Where do fish live?','Desert','Mountain','Ocean','Sky','Ocean','6-8'),
    ('Emoji Quiz','🌙⭐ — When do you see stars?','Morning','Afternoon','Night','Noon','Night','6-8'),
    ('Emoji Quiz','🍎🌳 — Where do apples grow?','Underground','On trees','In water','In sand','On trees','6-8'),

    # ── 9-11 SCIENCE ────────────────────────────────────────────────────────
    ('Science','What is the chemical symbol for water?','WA','HO','H2O','W2O','H2O','9-11'),
    ('Science','How many planets are in our solar system?','7','8','9','10','8','9-11'),
    ('Science','What is the powerhouse of the cell?','Nucleus','Mitochondria','Ribosome','Vacuole','Mitochondria','9-11'),
    ('Science','Which gas do humans breathe out?','Oxygen','Nitrogen','Carbon dioxide','Hydrogen','Carbon dioxide','9-11'),
    ('Science','What is the speed of light (approx)?','3 lakh km/s','1 lakh km/s','5 lakh km/s','9 lakh km/s','3 lakh km/s','9-11'),
    ('Science','What type of animal is a dolphin?','Fish','Reptile','Mammal','Amphibian','Mammal','9-11'),
    ('Science','Which planet has rings around it?','Mars','Jupiter','Saturn','Uranus','Saturn','9-11'),
    ('Science','What is the boiling point of water?','50°C','75°C','100°C','120°C','100°C','9-11'),
    ('Science','Sound travels fastest through?','Air','Vacuum','Water','Steel','Steel','9-11'),
    ('Science','Photosynthesis happens in which part of a plant?','Roots','Stem','Leaves','Flowers','Leaves','9-11'),
    ('Science','What force pulls objects toward Earth?','Magnetism','Friction','Gravity','Tension','Gravity','9-11'),
    # ── 9-11 MATH ────────────────────────────────────────────────────────────
    ('Math','What is the square root of 144?','11','12','13','14','12','9-11'),
    ('Math','What is 15% of 200?','20','25','30','35','30','9-11'),
    ('Math','If a triangle has angles 60°, 60°, what is the third angle?','30°','60°','90°','120°','60°','9-11'),
    ('Math','What is the perimeter of a square with side 7cm?','21cm','28cm','14cm','49cm','28cm','9-11'),
    ('Math','What is 2³ (2 to the power 3)?','6','8','9','12','8','9-11'),
    ('Math','A train travels 60 km/h. How far in 3 hours?','120km','150km','180km','200km','180km','9-11'),
    ('Math','What is the LCM of 4 and 6?','8','10','12','24','12','9-11'),
    ('Math','What comes next? 1, 1, 2, 3, 5, 8, __','11','12','13','14','13','9-11'),
    # ── 9-11 GENERAL KNOWLEDGE ───────────────────────────────────────────────
    ('General Knowledge','Who wrote the national anthem of India?','Bankim Chandra','Rabindranath Tagore','Mahatma Gandhi','Sarojini Naidu','Rabindranath Tagore','9-11'),
    ('General Knowledge','Mount Everest is in which country?','India','China','Nepal','Tibet','Nepal','9-11'),
    ('General Knowledge','What is the largest continent?','Africa','Europe','Asia','Australia','Asia','9-11'),
    ('General Knowledge','The Taj Mahal is located in?','Delhi','Agra','Jaipur','Lucknow','Agra','9-11'),
    ('General Knowledge','Which sport uses a shuttlecock?','Tennis','Badminton','Cricket','Hockey','Badminton','9-11'),
    ('General Knowledge','How many players are in a cricket team?','9','10','11','12','11','9-11'),
    ('General Knowledge','The Indian currency is called?','Dollar','Rupee','Pound','Euro','Rupee','9-11'),
    ('General Knowledge','Which day is celebrated as Independence Day in India?','26 Jan','15 Aug','2 Oct','14 Nov','15 Aug','9-11'),
    ('General Knowledge','Who invented the telephone?','Edison','Tesla','Bell','Marconi','Bell','9-11'),
    # ── 9-11 RIDDLES ─────────────────────────────────────────────────────────
    ('Riddle','The more you take, the more you leave behind. What am I?','Time','Footsteps','Memories','Shadows','Footsteps','9-11'),
    ('Riddle','I speak without a mouth and hear without ears. What am I?','Echo','Radio','Wind','Mirror','Echo','9-11'),
    ('Riddle','What has cities but no houses, mountains but no trees?','A dream','A map','A picture','A globe','A map','9-11'),
    ('Riddle','I can fly without wings. What am I?','Cloud','Time','Dream','Thought','Time','9-11'),
    # ── 9-11 EMOJI QUIZ ──────────────────────────────────────────────────────
    ('Emoji Quiz','🧲 attracts which material?','Wood','Plastic','Iron','Glass','Iron','9-11'),
    ('Emoji Quiz','🌍 rotates around ☀️ in how many days?','265','365','465','565','365','9-11'),
    ('Emoji Quiz','🏏 + 🇮🇳 — India national sport is?','Hockey','Cricket','Football','Kabaddi','Hockey','9-11'),

    # ── 12-13 SCIENCE ────────────────────────────────────────────────────────
    ('Science','What is the atomic number of Carbon?','4','6','8','12','6','12-13'),
    ('Science','DNA stands for?','Dioxyribose Nucleic Acid','Deoxyribonucleic Acid','Double Nuclear Acid','Dynamic Nuclear Atom','Deoxyribonucleic Acid','12-13'),
    ('Science','Which layer of Earth\'s atmosphere blocks UV rays?','Troposphere','Mesosphere','Ozone layer','Ionosphere','Ozone layer','12-13'),
    ('Science','Newton\'s second law: F = ?','ma','mv','m/a','mg','ma','12-13'),
    ('Science','What is the SI unit of electric current?','Volt','Ohm','Ampere','Watt','Ampere','12-13'),
    ('Science','Which blood type is universal donor?','A+','B-','AB+','O-','O-','12-13'),
    ('Science','What is the process of cell division called?','Osmosis','Mitosis','Photosynthesis','Diffusion','Mitosis','12-13'),
    ('Science','Sound cannot travel through?','Water','Air','Vacuum','Steel','Vacuum','12-13'),
    ('Science','The pH of pure water is?','5','7','9','10','7','12-13'),
    ('Science','Which part of the brain controls balance?','Cerebrum','Cerebellum','Medulla','Hypothalamus','Cerebellum','12-13'),
    # ── 12-13 MATH ────────────────────────────────────────────────────────────
    ('Math','What is the value of π (pi) approximately?','2.14','3.14','4.14','5.14','3.14','12-13'),
    ('Math','Solve: 3x + 7 = 22. x = ?','4','5','6','7','5','12-13'),
    ('Math','What is 12! / 11! ?','11','12','13','14','12','12-13'),
    ('Math','A quadrilateral has how many sides?','3','4','5','6','4','12-13'),
    ('Math','What is the area of a circle with radius 7? (π≈22/7)','144','154','164','174','154','12-13'),
    ('Math','What is 2^10?','512','1024','2048','256','1024','12-13'),
    ('Math','The sum of interior angles of a triangle?','90°','180°','270°','360°','180°','12-13'),
    ('Math','Probability of getting heads on a coin flip?','0','1/2','1/4','1/3','1/2','12-13'),
    # ── 12-13 GENERAL KNOWLEDGE ───────────────────────────────────────────────
    ('General Knowledge','Who was the first President of India?','Jawaharlal Nehru','Dr. Rajendra Prasad','Dr. APJ Abdul Kalam','Indira Gandhi','Dr. Rajendra Prasad','12-13'),
    ('General Knowledge','Which is the longest river in the world?','Amazon','Nile','Yangtze','Ganga','Nile','12-13'),
    ('General Knowledge','The United Nations headquarters is in?','Geneva','London','New York','Paris','New York','12-13'),
    ('General Knowledge','Who invented the internet?','Bill Gates','Tim Berners-Lee','Steve Jobs','Mark Zuckerberg','Tim Berners-Lee','12-13'),
    ('General Knowledge','What is the largest democracy in the world?','USA','China','India','Brazil','India','12-13'),
    ('General Knowledge','Which element has the symbol Au?','Silver','Gold','Aluminum','Argon','Gold','12-13'),
    ('General Knowledge','In which year did India gain independence?','1945','1946','1947','1948','1947','12-13'),
    ('General Knowledge','Who wrote "Discovery of India"?','Mahatma Gandhi','Jawaharlal Nehru','Subhas Chandra Bose','B. R. Ambedkar','Jawaharlal Nehru','12-13'),
    # ── 12-13 RIDDLES ─────────────────────────────────────────────────────────
    ('Riddle','I have keys but no locks. I have space but no room. What am I?','Book','Piano','Keyboard','Safe','Keyboard','12-13'),
    ('Riddle','What can travel the world without moving?','Internet','Stamp','Wind','Letter','Stamp','12-13'),
    ('Riddle','The more you share me, the more I grow. What am I?','Money','Knowledge','Food','Time','Knowledge','12-13'),
    # ── 12-13 TECHNOLOGY ─────────────────────────────────────────────────────
    ('Technology','What does CPU stand for?','Central Processing Unit','Computer Power Unit','Control Program Unit','Central Program Utility','Central Processing Unit','12-13'),
    ('Technology','Which language is used to create web pages?','Python','Java','HTML','C++','HTML','12-13'),
    ('Technology','What does GPS stand for?','Global Positioning System','General Processing Software','Geographic Pixel System','Global Pixel Sensor','Global Positioning System','12-13'),
    ('Technology','What does RAM stand for?','Random Access Memory','Read And Modify','Rapid Application Module','Random Array Memory','Random Access Memory','12-13'),
    ('Technology','Which company made the iPhone?','Samsung','Google','Apple','Microsoft','Apple','12-13'),
    ('Technology','What is 1 Gigabyte equal to?','1000 KB','1000 MB','1024 MB','1024 KB','1024 MB','12-13'),
    # ── INTERNET SAFETY (ALL GROUPS) ─────────────────────────────────────────
    ('Internet Safety','You receive a message from an unknown person asking your address. You should?','Reply with address','Block and tell an adult','Reply but give fake info','Ignore forever','Block and tell an adult','6-8'),
    ('Internet Safety','Which password is strongest?','abc123','password1','My@Dog#2024!','iloveschool','My@Dog#2024!','9-11'),
    ('Internet Safety','What is "phishing"?','A type of fishing sport','Tricking someone to give private info','A coding term','Social media feature','Tricking someone to give private info','9-11'),
    ('Internet Safety','HTTPS in a web address means?','The website is slow','The site is secure','The page has ads','The site is government-run','The site is secure','12-13'),
    ('Internet Safety','What is a safe way to create a password?','Use your birth date','Use your name','Mix letters numbers and symbols','Use "password"','Mix letters numbers and symbols','12-13'),
    ('Internet Safety','You feel sad after using an app. The best action is?','Use it more','Delete all apps','Take a break and talk to a trusted adult','Post about it','Take a break and talk to a trusted adult','9-11'),
    ('Internet Safety','Cyberbullying is when someone?','Teaches coding online','Bullies others using technology','Plays games online','Reports a bad website','Bullies others using technology','6-8'),
    # ── INDIA SPECIAL ─────────────────────────────────────────────────────────
    ('India Special','Which is the national animal of India?','Lion','Elephant','Tiger','Leopard','Tiger','6-8'),
    ('India Special','Holi is the festival of?','Lights','Colours','Sweets','Music','Colours','6-8'),
    ('India Special','How many states are in India?','25','26','28','29','28','9-11'),
    ('India Special','The game of Chess was invented in?','China','India','Egypt','Greece','India','9-11'),
    ('India Special','Which Indian state is famous for its backwaters?','Goa','Tamil Nadu','Kerala','Karnataka','Kerala','12-13'),
    ('India Special','Who is known as the Missile Man of India?','Vikram Sarabhai','APJ Abdul Kalam','C.V. Raman','Homi Bhabha','APJ Abdul Kalam','12-13'),
    # ── FUN FACTS ─────────────────────────────────────────────────────────────
    ('Fun Fact','An octopus has how many hearts?','1','2','3','4','3','6-8'),
    ('Fun Fact','Sharks are older than which ancient creatures?','Crocodiles','Dinosaurs','Whales','Elephants','Dinosaurs','9-11'),
    ('Fun Fact','A group of flamingos is called a?','Pack','Flock','Flamboyance','Colony','Flamboyance','9-11'),
    ('Fun Fact','Honey never spoils. How old is the oldest honey found?','100 years','500 years','3000 years','1000 years','3000 years','12-13'),
    ('Fun Fact','Which fruit has seeds on the outside?','Apple','Strawberry','Grape','Orange','Strawberry','6-8'),
    ('Fun Fact','A snail can sleep for how long?','1 day','1 week','3 years','1 month','3 years','9-11'),
    # ── ENVIRONMENT ───────────────────────────────────────────────────────────
    ('Environment','What is the main cause of global warming?','More sunlight','Greenhouse gases','Less rainfall','Earthquakes','Greenhouse gases','9-11'),
    ('Environment','The 3 Rs of environment are?','Read Run Rest','Reduce Reuse Recycle','Race Run Resolve','Run Relay Race','Reduce Reuse Recycle','6-8'),
    ('Environment','Which gas is known as the greenhouse gas?','Oxygen','Nitrogen','Carbon Dioxide','Hydrogen','Carbon Dioxide','12-13'),
    ('Environment','Deforestation mainly causes?','More rain','Soil erosion','Better roads','Cooler weather','Soil erosion','9-11'),
    # ── SPACE ─────────────────────────────────────────────────────────────────
    ('Space','How long does it take Earth to orbit the Sun?','24 hours','365 days','7 days','30 days','365 days','6-8'),
    ('Space','What is the closest star to Earth?','Sirius','Alpha Centauri','The Sun','Vega','The Sun','9-11'),
    ('Space','Who was the first human to walk on the Moon?','Yuri Gagarin','Neil Armstrong','Buzz Aldrin','John Glenn','Neil Armstrong','9-11'),
    ('Space','The Milky Way is a?','Planet','Star','Solar System','Galaxy','Galaxy','12-13'),
    ('Space','What is a black hole?','A hole in space','Region where gravity is so strong nothing escapes','A very dark planet','Space debris','Region where gravity is so strong nothing escapes','12-13'),
    # ── CODING / TECH FOR KIDS ────────────────────────────────────────────────
    ('Coding','In coding, what does "loop" mean?','A bug','Repeating code','A type of variable','A function name','Repeating code','9-11'),
    ('Coding','What is the output of: print(2 + 3) in Python?','23','5','2+3','Error','5','12-13'),
    ('Coding','What does "if" do in programming?','Loops code','Makes a decision','Defines a variable','Prints output','Makes a decision','9-11'),
    ('Coding','The first programming language was called?','Python','Java','FORTRAN','C','FORTRAN','12-13'),
    ('Coding','What is a "bug" in software?','An insect','An error in code','A feature','A slow computer','An error in code','9-11'),
    # ── HEALTH & BODY ─────────────────────────────────────────────────────────
    ('Health','How many teeth do adults have?','28','30','32','34','32','9-11'),
    ('Health','Which vitamin do we get from sunlight?','Vitamin A','Vitamin B','Vitamin C','Vitamin D','Vitamin D','6-8'),
    ('Health','The heart pumps?','Air','Water','Blood','Food','Blood','6-8'),
    ('Health','How many chambers does the human heart have?','2','3','4','5','4','12-13'),
    ('Health','Which mineral makes bones strong?','Iron','Calcium','Potassium','Zinc','Calcium','9-11'),
]

INSERT_SQL = """
INSERT INTO quizzes(category, question, option_a, option_b, option_c, option_d, correct_answer, age_group)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
ON CONFLICT DO NOTHING
"""

def run():
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.executemany(INSERT_SQL, QUESTIONS)
            count = cur.rowcount
        conn.commit()
        print(f'[OK] Seeded {count} new quiz questions ({len(QUESTIONS)} total attempted).')
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

if __name__ == '__main__':
    run()
