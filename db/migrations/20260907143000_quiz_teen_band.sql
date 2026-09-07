-- migrate:up
-- LittleNet accounts support children through age 18, so the mandatory quiz
-- latch must always have an age-authorized question available for teens.
ALTER TABLE quizzes DROP CONSTRAINT IF EXISTS quizzes_age_group_check;
ALTER TABLE quizzes ADD CONSTRAINT quizzes_age_group_check
  CHECK(age_group IN ('6-8','9-11','12-13','14-18'));

WITH teen_questions(category,question,option_a,option_b,option_c,option_d,correct_answer,age_group) AS (
  VALUES
  ('Digital Safety','A stranger asks to move a LittleNet chat to a private app. What is safest?','Move the chat','Share your number','Keep the conversation on the approved platform and tell a trusted adult','Delete all evidence','Keep the conversation on the approved platform and tell a trusted adult','14-18'),
  ('Digital Safety','What should you do before enabling two-factor authentication?','Reuse an old password','Use a trusted authenticator or verified phone method','Share recovery codes with friends','Disable your password','Use a trusted authenticator or verified phone method','14-18'),
  ('Digital Safety','Someone threatens to publish a private image unless you comply. What should you do?','Pay them','Send more images','Preserve evidence, block/report them, and tell a trusted adult','Meet them alone','Preserve evidence, block/report them, and tell a trusted adult','14-18'),
  ('Digital Literacy','What is the best first check for a surprising viral claim?','Number of likes','A reliable primary or reputable source','Whether a friend reposted it','How dramatic the headline is','A reliable primary or reputable source','14-18'),
  ('Digital Literacy','Why should AI-generated information be verified?','AI is always offline','AI can produce confident but incorrect information','AI never uses text','Verification makes files smaller','AI can produce confident but incorrect information','14-18'),
  ('Technology','What does HTTPS primarily protect in web browsing?','Screen brightness','Data in transit between browser and server','Battery health','File names on your desktop','Data in transit between browser and server','14-18'),
  ('Technology','Which practice best protects a software API key?','Commit it to GitHub','Put it in screenshots','Store it in a secret manager or protected environment variable','Share it in group chat','Store it in a secret manager or protected environment variable','14-18'),
  ('Technology','What is phishing?','Compressing a file','A deceptive attempt to steal information or credentials','Updating software','Encrypting a disk','A deceptive attempt to steal information or credentials','14-18'),
  ('Science','Which molecule carries most hereditary information in humans?','DNA','Water','Glucose','Oxygen','DNA','14-18'),
  ('Science','What is the approximate acceleration due to gravity near Earth surface?','9.8 m/s²','98 m/s²','0.98 m/s²','980 m/s²','9.8 m/s²','14-18'),
  ('Science','Which process converts glucose and oxygen into usable cellular energy?','Photosynthesis','Cellular respiration','Osmosis','Transpiration','Cellular respiration','14-18'),
  ('Math','Solve 2x + 5 = 19. What is x?','5','6','7','12','7','14-18'),
  ('Math','What is 25% of 360?','45','72','90','120','90','14-18'),
  ('Math','If a right triangle has legs 3 and 4, its hypotenuse is?','5','6','7','8','5','14-18'),
  ('General Knowledge','Which branch of government typically interprets laws?','Judiciary','Executive only','Media','Private companies','Judiciary','14-18'),
  ('General Knowledge','What does GDP commonly measure?','Only population','The value of goods and services produced in an economy','Rainfall','Internet speed','The value of goods and services produced in an economy','14-18'),
  ('Cyber Safety','A website asks for your password after you clicked an unexpected link. What should you do?','Enter it quickly','Close the page and navigate to the official site yourself','Send the link to friends','Reuse another password','Close the page and navigate to the official site yourself','14-18'),
  ('Cyber Safety','Which password is generally strongest?','password123','Your birthday','A long unique passphrase not reused elsewhere','Your first name','A long unique passphrase not reused elsewhere','14-18'),
  ('Kindness','A classmate is being targeted in a group chat. What is the best response?','Join in','Forward the messages publicly','Support the classmate and report the abuse through trusted channels','Ignore every situation','Support the classmate and report the abuse through trusted channels','14-18'),
  ('Critical Thinking','Two sources disagree about a factual claim. What should you do?','Choose the louder source','Compare evidence, authorship, date, and independent reliable sources','Pick the first result','Assume both are false','Compare evidence, authorship, date, and independent reliable sources','14-18')
)
INSERT INTO quizzes(category,question,option_a,option_b,option_c,option_d,correct_answer,age_group)
SELECT tq.* FROM teen_questions tq
WHERE NOT EXISTS (
  SELECT 1 FROM quizzes q
  WHERE q.question=tq.question AND q.age_group='14-18'
);

-- migrate:down
DELETE FROM quizzes WHERE age_group='14-18' AND question IN (
  'A stranger asks to move a LittleNet chat to a private app. What is safest?',
  'What should you do before enabling two-factor authentication?',
  'Someone threatens to publish a private image unless you comply. What should you do?',
  'What is the best first check for a surprising viral claim?',
  'Why should AI-generated information be verified?',
  'What does HTTPS primarily protect in web browsing?',
  'Which practice best protects a software API key?',
  'What is phishing?',
  'Which molecule carries most hereditary information in humans?',
  'What is the approximate acceleration due to gravity near Earth surface?',
  'Which process converts glucose and oxygen into usable cellular energy?',
  'Solve 2x + 5 = 19. What is x?',
  'What is 25% of 360?',
  'If a right triangle has legs 3 and 4, its hypotenuse is?',
  'Which branch of government typically interprets laws?',
  'What does GDP commonly measure?',
  'A website asks for your password after you clicked an unexpected link. What should you do?',
  'Which password is generally strongest?',
  'A classmate is being targeted in a group chat. What is the best response?',
  'Two sources disagree about a factual claim. What should you do?'
);
ALTER TABLE quizzes DROP CONSTRAINT IF EXISTS quizzes_age_group_check;
ALTER TABLE quizzes ADD CONSTRAINT quizzes_age_group_check
  CHECK(age_group IN ('6-8','9-11','12-13'));
