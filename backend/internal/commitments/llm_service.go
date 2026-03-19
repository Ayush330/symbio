package commitments

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"strings"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

type FavourCategory string

const (
	CategoryHealth       FavourCategory = "health"
	CategoryFamily       FavourCategory = "family"
	CategoryMoney        FavourCategory = "money"
	CategoryCareer       FavourCategory = "career"
	CategoryStartup      FavourCategory = "startup"
	CategoryEmotional    FavourCategory = "emotional"
	CategoryEducation    FavourCategory = "education"
	CategoryMentorship   FavourCategory = "mentorship"
	CategoryNetworking   FavourCategory = "networking"
	CategoryTech         FavourCategory = "tech"
	CategoryTravel       FavourCategory = "travel"
	CategoryCommunity    FavourCategory = "community"
	CategorySocial       FavourCategory = "social"
	CategoryHousehold    FavourCategory = "household"
	CategoryFitness      FavourCategory = "fitness"
	CategoryFood         FavourCategory = "food"
	CategoryFun          FavourCategory = "fun"
	CategoryEmergency    FavourCategory = "emergency"
	CategoryLegal        FavourCategory = "legal"
	CategoryRelationship FavourCategory = "relationship"
	CategoryOther        FavourCategory = "other"
)

var CategoryWeights = map[FavourCategory]int{
	CategoryEmergency:    100,
	CategoryHealth:       95,
	CategoryFamily:       90,
	CategoryMoney:        85,
	CategoryLegal:        85,
	CategoryCareer:       80,
	CategoryStartup:      80,
	CategoryEmotional:    75,
	CategoryRelationship: 75,
	CategoryEducation:    70,
	CategoryMentorship:   70,
	CategoryNetworking:   65,
	CategoryTech:         65,
	CategoryTravel:       60,
	CategoryCommunity:    60,
	CategorySocial:       55,
	CategoryHousehold:    50,
	CategoryFitness:      45,
	CategoryFood:         35,
	CategoryFun:          25,
	CategoryOther:        10,
}

// KarmaMetrics represents the 5 dimensions of a favor
type KarmaMetrics struct {
	CategoryWeight int     `json:"category_weight"`
	Effort         int     `json:"effort"`    // 1-5
	Time           int     `json:"time"`      // 1-5
	Sacrifice      int     `json:"sacrifice"` // 1-5
	Urgency        int     `json:"urgency"`   // 1-5
	Intensity      float64 `json:"intensity"`
	Intensity100   float64 `json:"intensity_100"`
	FinalScore     int     `json:"final_score"`
	Explanation    string  `json:"explanation"`
}

// Classifier defines the interface for categorization logic
type Classifier interface {
	Classify(ctx context.Context, text string) (FavourCategory, int, error)
	Analyze(ctx context.Context, text string) (*KarmaMetrics, error)
}

// KeywordClassifier is the legacy/fallback keyword implementation
type KeywordClassifier struct{}

func (k *KeywordClassifier) Classify(ctx context.Context, text string) (FavourCategory, int, error) {
	text = strings.ToLower(text)
	// Fallback logic could be complex, but for now we look for keywords in common categories
	cat := CategoryOther
	if containsAny(text, "health", "doctor", "medicine", "gym", "workout", "sick") {
		cat = CategoryHealth
	} else if containsAny(text, "money", "cash", "paid", "bill", "rent", "loan", "split") {
		cat = CategoryMoney
	}

	metrics := k.calculateDeterministic(cat, 3, 3, 2, 2, "Keyword fallback")
	return cat, metrics.FinalScore, nil
}

func (k *KeywordClassifier) Analyze(ctx context.Context, text string) (*KarmaMetrics, error) {
	cat, _, _ := k.Classify(ctx, text)
	return k.calculateDeterministic(cat, 3, 3, 2, 2, "Keyword fallback analysis"), nil
}

func (k *KeywordClassifier) calculateDeterministic(cat FavourCategory, effort, time, sacrifice, urgency int, explanation string) *KarmaMetrics {
	weight := CategoryWeights[cat]
	if weight == 0 {
		weight = 10
	}

	// Step 1: intensity = 5 * (effort + time + sacrifice + urgency) / 4
	intensity := 5.0 * float64(effort+time+sacrifice+urgency) / 4.0
	// Step 2: intensity_100 = intensity * 4
	intensity100 := intensity * 4.0
	// Step 3: score = category_weight * intensity_100 / 100
	score := float64(weight) * intensity100 / 100.0
	// Step 4: Clamp score between 1 and 100
	finalScore := int(math.Round(score))
	if finalScore < 1 {
		finalScore = 1
	}
	if finalScore > 100 {
		finalScore = 100
	}

	return &KarmaMetrics{
		CategoryWeight: weight,
		Effort:         effort,
		Time:           time,
		Sacrifice:      sacrifice,
		Urgency:        urgency,
		Intensity:      intensity,
		Intensity100:   intensity100,
		FinalScore:     finalScore,
		Explanation:    explanation,
	}
}

// GeminiClassifier uses Google's Gemini API for classification
type GeminiClassifier struct {
	ApiKey   string
	Fallback *KeywordClassifier
}

func (g *GeminiClassifier) Classify(ctx context.Context, text string) (FavourCategory, int, error) {
	metrics, err := g.Analyze(ctx, text)
	if err != nil {
		return g.Fallback.Classify(ctx, text)
	}
	// Extract category from explanation or reverse map? Better if Analyze returns it.
	// We'll update Gemini for that.
	return CategoryOther, metrics.FinalScore, nil
}

func (g *GeminiClassifier) Analyze(ctx context.Context, text string) (*KarmaMetrics, error) {
	if g.ApiKey == "" {
		log.Println("No API key provided, using fallback")
		return g.Fallback.Analyze(ctx, text)
	}

	client, err := genai.NewClient(ctx, option.WithAPIKey(g.ApiKey))
	if err != nil {
		return g.Fallback.Analyze(ctx, text)
	}
	defer client.Close()

	model := client.GenerativeModel("gemini-1.5-flash")
	model.ResponseMIMEType = "application/json"

	prompt := fmt.Sprintf(`
Analyze this favor and return a JSON object with:
- "category": choose from %v
- "effort": 1-5 scale
- "time": 1-5 scale
- "sacrifice": 1-5 scale
- "urgency": 1-5 scale
- "explanation": very short text

Favor: "%s"

JSON Schema:
{
  "category": string,
  "effort": integer,
  "time": integer,
  "sacrifice": integer,
  "urgency": integer,
  "explanation": string
}`, getAllCategories(), text)

	resp, err := model.GenerateContent(ctx, genai.Text(prompt))
	if err != nil {
		return g.Fallback.Analyze(ctx, text)
	}

	part := ""
	for _, p := range resp.Candidates[0].Content.Parts {
		if t, ok := p.(genai.Text); ok {
			part += string(t)
		}
	}

	log.Printf("GEMINI RAW RESPONSE: %s", part)

	var geminiResp struct {
		Category    string `json:"category"`
		Effort      int    `json:"effort"`
		Time        int    `json:"time"`
		Sacrifice   int    `json:"sacrifice"`
		Urgency     int    `json:"urgency"`
		Explanation string `json:"explanation"`
	}

	if err := json.Unmarshal([]byte(part), &geminiResp); err != nil {
		log.Printf("Failed to unmarshal Gemini JSON: %v", err)
		return g.Fallback.Analyze(ctx, text)
	}

	return g.Fallback.calculateDeterministic(FavourCategory(strings.ToLower(geminiResp.Category)), geminiResp.Effort, geminiResp.Time, geminiResp.Sacrifice, geminiResp.Urgency, geminiResp.Explanation), nil
}

func getAllCategories() []string {
	var cats []string
	for k := range CategoryWeights {
		cats = append(cats, string(k))
	}
	return cats
}

func containsAny(text string, keywords ...string) bool {
	for _, kw := range keywords {
		if strings.Contains(text, kw) {
			return true
		}
	}
	return false
}
