package main

import (
	"testing"
	"github.com/stretchr/testify/assert"
)

func TestClientStruct(t *testing.T) {
	c := &Client{ID: "test-client"}
	assert.Equal(t, "test-client", c.ID)
}
