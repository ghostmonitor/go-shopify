package goshopify

import (
	"fmt"
	"time"
)

const (
	discountCodeBasePath = "price_rules/%d/discount_codes"

	DiscountCodeCreationJobStatusQueued    = "queued"
	DiscountCodeCreationJobStatusRunning   = "running"
	DiscountCodeCreationJobStatusCompleted = "completed"
)

// DiscountCodeService is an interface for interfacing with the discount endpoints
// of the Shopify API.
// See: https://help.shopify.com/en/api/reference/discounts/PriceRuleDiscountCode
type DiscountCodeService interface {
	Create(int64, PriceRuleDiscountCode) (*PriceRuleDiscountCode, error)
	Update(int64, PriceRuleDiscountCode) (*PriceRuleDiscountCode, error)
	List(int64) ([]PriceRuleDiscountCode, error)
	Get(int64, int64) (*PriceRuleDiscountCode, error)
	Delete(int64, int64) error
}

// DiscountCodeServiceOp handles communication with the discount code
// related methods of the Shopify API.
type DiscountCodeServiceOp struct {
	client *Client
}

// PriceRuleDiscountCode represents a Shopify Discount Code
type PriceRuleDiscountCode struct {
	ID          int64      `json:"id,omitempty"`
	PriceRuleID int64      `json:"price_rule_id,omitempty"`
	Code        string     `json:"code,omitempty"`
	UsageCount  int        `json:"usage_count,omitempty"`
	CreatedAt   *time.Time `json:"created_at,omitempty"`
	UpdatedAt   *time.Time `json:"updated_at,omitempty"`
}

// DiscountCodesResource is the result from the discount_codes.json endpoint
type DiscountCodesResource struct {
	DiscountCodes []PriceRuleDiscountCode `json:"discount_codes"`
}

// DiscountCodeResource represents the result from the discount_codes/X.json endpoint
type DiscountCodeResource struct {
	PriceRuleDiscountCode *PriceRuleDiscountCode `json:"discount_code"`
}

type DiscountCodeCreationJobRequest struct {
	DiscountCodes []*DiscountCodeCreationJobDiscountCode `json:"discount_codes"`
}

type DiscountCodeCreationJobResponse struct {
	DiscountCodeCreationJob *DiscountCodeCreationJob `json:"discount_code_creation"`
}

type DiscountCodeCreationJobDiscountCodesResponse struct {
	DiscountCodes []*DiscountCodeCreationJobDiscountCode `json:"discount_codes"`
}

type DiscountCodeCreationJobDiscountCode struct {
	ID     int64               `json:"id,omitempty"`
	Code   string              `json:"code,omitempty"`
	Errors map[string][]string `json:"errors,omitempty"`
}

type DiscountCodeCreationDiscountCodeError struct {
	Code []string `json:"code"`
}

type DiscountCodeCreationJob struct {
	ID            int64     `json:"id"`
	PriceRuleID   int64     `json:"price_rule_id"`
	StartedAt     time.Time `json:"started_at"`
	CompletedAt   time.Time `json:"completed_at"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
	Status        string    `json:"status"`
	CodesCount    uint8     `json:"codes_count"`
	ImportedCount uint8     `json:"imported_count"`
	FailedCount   uint8     `json:"failed_count"`
}

// Create a discount code
func (s *DiscountCodeServiceOp) Create(priceRuleID int64, dc PriceRuleDiscountCode) (*PriceRuleDiscountCode, error) {
	path := fmt.Sprintf(discountCodeBasePath+".json", priceRuleID)
	wrappedData := DiscountCodeResource{PriceRuleDiscountCode: &dc}
	resource := new(DiscountCodeResource)
	err := s.client.Post(path, wrappedData, resource)
	return resource.PriceRuleDiscountCode, err
}

// Update an existing discount code
func (s *DiscountCodeServiceOp) Update(priceRuleID int64, dc PriceRuleDiscountCode) (*PriceRuleDiscountCode, error) {
	path := fmt.Sprintf(discountCodeBasePath+"/%d.json", priceRuleID, dc.ID)
	wrappedData := DiscountCodeResource{PriceRuleDiscountCode: &dc}
	resource := new(DiscountCodeResource)
	err := s.client.Put(path, wrappedData, resource)
	return resource.PriceRuleDiscountCode, err
}

// List of discount codes
func (s *DiscountCodeServiceOp) List(priceRuleID int64) ([]PriceRuleDiscountCode, error) {
	path := fmt.Sprintf(discountCodeBasePath+".json", priceRuleID)
	resource := new(DiscountCodesResource)
	err := s.client.Get(path, resource, nil)
	return resource.DiscountCodes, err
}

// Get a single discount code
func (s *DiscountCodeServiceOp) Get(priceRuleID int64, discountCodeID int64) (*PriceRuleDiscountCode, error) {
	path := fmt.Sprintf(discountCodeBasePath+"/%d.json", priceRuleID, discountCodeID)
	resource := new(DiscountCodeResource)
	err := s.client.Get(path, resource, nil)
	return resource.PriceRuleDiscountCode, err
}

// Delete a discount code
func (s *DiscountCodeServiceOp) Delete(priceRuleID int64, discountCodeID int64) error {
	return s.client.Delete(fmt.Sprintf(discountCodeBasePath+"/%d.json", priceRuleID, discountCodeID))
}
