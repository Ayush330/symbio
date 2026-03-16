package commitments

import (
	"strings"
)

type FavourCategory string

const (
	CategoryHealth    FavourCategory = "health"
	CategoryMoney     FavourCategory = "money"
	CategoryHelp      FavourCategory = "help"
	CategoryEmotional FavourCategory = "emotional"
	CategoryOther     FavourCategory = "other"
)

func ClassifyFavour(text string) (string, int) {
	text = strings.ToLower(text)
	
	// Simple keyword-based classifier as a robust starting point/fallback
	if containsAny(text, "health", "doctor", "medicine", "gym", "workout", "sick") {
		return string(CategoryHealth), 50
	}
	if containsAny(text, "money", "cash", "paid", "bill", "rent", "loan", "split") {
		return string(CategoryMoney), 40
	}
	if containsAny(text, "help", "assisted", "interview", "prep", "job", "career") {
		return string(CategoryHelp), 30
	}
	if containsAny(text, "emotional", "support", "talk", "listen", "vent", "advice") {
		return string(CategoryEmotional), 20
	}
	
	return string(CategoryOther), 10
}

func containsAny(text string, keywords ...string) bool {
	for _, kw := range keywords {
		if strings.Contains(text, kw) {
			return true
		}
	}
	return false
}
