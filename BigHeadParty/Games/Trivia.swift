import Foundation

struct TriviaQuestion: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    let options: [String]
    let answer: Int
    let quip: String
}

/// Silly-but-true trivia. Facts only; the jokes are in the quips.
enum TriviaBank {
    static let all: [TriviaQuestion] = [
        .init(prompt: "What is Scotland's national animal?", options: ["Haggis", "Unicorn", "Loch Ness Monster"], answer: 1, quip: "Majestic. Fictional. Official."),
        .init(prompt: "How many hearts does an octopus have?", options: ["1", "3", "8"], answer: 1, quip: "Three hearts and still no valentine."),
        .init(prompt: "Which of these is technically a berry?", options: ["Strawberry", "Raspberry", "Banana"], answer: 2, quip: "Botany is a liar."),
        .init(prompt: "What color is a polar bear's skin?", options: ["White", "Black", "Pink"], answer: 1, quip: "The fur is a disguise."),
        .init(prompt: "A group of flamingos is called a…", options: ["Flamboyance", "Fiesta", "Feather duster"], answer: 0, quip: "Fabulous, darling."),
        .init(prompt: "What was the first food John Glenn ate in orbit?", options: ["Pizza", "Applesauce", "Jelly beans"], answer: 1, quip: "From a tube. Living the dream."),
        .init(prompt: "Which planet spins backwards compared to most?", options: ["Mars", "Venus", "Jupiter"], answer: 1, quip: "Venus does what Venus wants."),
        .init(prompt: "What is a baby kangaroo called?", options: ["Joey", "Kit", "Pouchling"], answer: 0, quip: "Pouchling should be real though."),
        .init(prompt: "Which of these animals can't jump?", options: ["Frog", "Kangaroo", "Elephant"], answer: 2, quip: "Never once. Not even for cake."),
        .init(prompt: "What's a group of crows called?", options: ["A squad", "A murder", "A gossip"], answer: 1, quip: "Dramatic birds."),
        .init(prompt: "Which is the only mammal that can truly fly?", options: ["Flying squirrel", "Bat", "Sugar glider"], answer: 1, quip: "The squirrel is just gliding with confidence."),
        .init(prompt: "How many bones does an adult human have?", options: ["186", "206", "256"], answer: 1, quip: "Babies have more. Spooky."),
        .init(prompt: "Wombat poop is shaped like…", options: ["Stars", "Cubes", "Spirals"], answer: 1, quip: "Nature's dice."),
        .init(prompt: "Which country has the most pyramids?", options: ["Egypt", "Sudan", "Mexico"], answer: 1, quip: "Egypt is shook."),
        .init(prompt: "What's the dot over a lowercase 'i' called?", options: ["A tittle", "A jot", "A speck"], answer: 0, quip: "Yes, really. Stop giggling."),
        .init(prompt: "Whose fingerprints are nearly identical to humans'?", options: ["Panda", "Koala", "Raccoon"], answer: 1, quip: "The perfect crime."),
        .init(prompt: "Ketchup was sold in the 1830s as…", options: ["Paint", "Medicine", "Perfume"], answer: 1, quip: "Doctor's orders: fries."),
        .init(prompt: "What is Scooby-Doo's full first name?", options: ["Scoobert", "Scoobathan", "Scoobington"], answer: 0, quip: "Scoobert. Say it with respect."),
        .init(prompt: "Which animal usually sleeps standing up?", options: ["Horse", "Cat", "Pig"], answer: 0, quip: "Power naps, literally."),
        .init(prompt: "A baker's dozen is how many?", options: ["12", "13", "14"], answer: 1, quip: "The extra one is for the baker. Obviously."),
        .init(prompt: "Bananas are slightly…", options: ["Magnetic", "Radioactive", "Carbonated"], answer: 1, quip: "Potassium-40. Eat responsibly."),
        .init(prompt: "Canada's official SUMMER sport is…", options: ["Hockey", "Lacrosse", "Curling"], answer: 1, quip: "Hockey only gets winter."),
        .init(prompt: "Which is older?", options: ["Oxford University", "The Aztec Empire", "They tie"], answer: 0, quip: "Oxford was teaching before Tenochtitlan was founded."),
        .init(prompt: "What color is a giraffe's tongue?", options: ["Pink", "Blue-black", "Green"], answer: 1, quip: "Built-in sunscreen."),
        .init(prompt: "How many noses does a slug have?", options: ["None", "One", "Four"], answer: 2, quip: "Four noses. Zero tissues."),
        .init(prompt: "Honey found in ancient Egyptian tombs was…", options: ["Turned to stone", "Still edible", "Pure sugar crystals"], answer: 1, quip: "Best-before date: never."),
        .init(prompt: "Which planet has the most known moons?", options: ["Earth", "Saturn", "Mars"], answer: 1, quip: "Saturn collects them like fridge magnets."),
        .init(prompt: "Which animal has rectangular pupils?", options: ["Goat", "Owl", "Shark"], answer: 0, quip: "Widescreen vision."),
        .init(prompt: "How many legs does a spider have?", options: ["6", "8", "10"], answer: 1, quip: "One for each shoe it doesn't own."),
        .init(prompt: "What's the largest organ of the human body?", options: ["Liver", "Skin", "Brain"], answer: 1, quip: "You're wearing it right now."),
        .init(prompt: "Sea otters hold hands while sleeping so they…", options: ["Stay warm", "Don't drift apart", "Look cute"], answer: 1, quip: "Also: look cute."),
        .init(prompt: "Which is the fastest land animal?", options: ["Cheetah", "Pronghorn", "Your aunt at a buffet"], answer: 0, quip: "Close race though."),
    ]
}
