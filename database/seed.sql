INSERT INTO quizzes(category,question,option_a,option_b,option_c,option_d,correct_answer,age_group) VALUES
('Internet Safety','What should you do if a stranger asks for your password?','Send it','Tell a trusted adult','Post it publicly','Ignore all adults','Tell a trusted adult','6-8'),
('Digital Etiquette','Which message is kind online?','You are stupid','Thank you for helping me','I will expose you','Nobody likes you','Thank you for helping me','9-11'),
('Cyber Safety','What is the safest response to suspicious links?','Open immediately','Forward to everyone','Do not open and tell an adult','Enter your password','Do not open and tell an adult','12-13'),
('Science','Water freezes at?','0°C','50°C','100°C','-100°C','0°C','6-8'),
('Math','What is 12 × 4?','16','36','48','124','48','9-11'),
('Kindness','A classmate makes a mistake online. What is the kind choice?','Make fun of them','Share a screenshot','Help them politely','Tell everyone','Help them politely','6-8'),
('Digital Safety','Which detail should stay private?','Favourite colour','Home address','Favourite book','Best subject','Home address','6-8'),
('Science','Which part of a plant usually takes in water from soil?','Flower','Roots','Fruit','Leaf tip','Roots','6-8'),
('Kindness','Someone is being left out of a group chat. What should you do?','Ignore them','Invite them kindly','Laugh about it','Post about them','Invite them kindly','9-11'),
('Digital Safety','A friend asks to use your account password. What is safest?','Share it once','Keep it private','Post it in chat','Use their password too','Keep it private','9-11'),
('Science','Which gas do plants use during photosynthesis?','Oxygen','Carbon dioxide','Helium','Hydrogen','Carbon dioxide','9-11'),
('Digital Safety','You receive a message threatening to share a private photo. What should you do first?','Pay the sender','Reply with another threat','Save evidence and tell a trusted adult','Delete your account immediately','Save evidence and tell a trusted adult','12-13'),
('Kindness','Which response best handles a hurtful comment?','Start a public fight','Respond calmly or report it','Share their personal details','Create a fake account','Respond calmly or report it','12-13'),
('Science','What mainly causes day and night on Earth?','The Moon moving','Earth rotating','Clouds moving','The Sun turning off','Earth rotating','12-13'),
('Digital Literacy','Before reposting surprising news, what should you do?','Share immediately','Check a reliable source','Add more dramatic text','Send it to strangers','Check a reliable source','12-13')
ON CONFLICT DO NOTHING;

INSERT INTO learning_challenges(title,description,challenge_type,prompt,expected_answer,age_group,points) VALUES
('Password Detective','Choose the strongest password idea.','CYBER_SAFETY','Which is safer: puppy123 or R7!mQ2#z?','R7!mQ2#z','6-8',10),
('Kind Comment Challenge','Practice writing a positive online response.','ACTIVITY','Write one kind sentence you could post for a friend.',NULL,'6-8',10),
('Spot the Phishing Clue','Think before you click unknown links.','CYBER_SAFETY','Should you open a prize link sent by a stranger? Answer yes or no.','no','9-11',15),
('Math Sprint','Solve a short mental-math challenge.','PUZZLE','What is 18 x 5?','90','9-11',15),
('Privacy Check','Learn what should stay private online.','CYBER_SAFETY','Should your home address be posted publicly? Answer yes or no.','no','12-13',20),
('Logic Pattern','Complete the number pattern.','PUZZLE','2, 4, 8, 16, ?','32','12-13',20),
('Digital Footprint','Think about long-term online impact.','ACTIVITY','Write one thing you should check before posting online.',NULL,'14-18',20),
('Security Reasoning','Recognize safer account behaviour.','CYBER_SAFETY','Is reusing one password everywhere safe? Answer yes or no.','no','14-18',20)
ON CONFLICT DO NOTHING;
