<?php

namespace Tests\Unit;

use App\Http\Controllers\Api\V1\CompanyPosDocumentTemplateController;
use Tests\TestCase;

class CompanyPosDocument21C4Test extends TestCase
{
    public function test_qr_and_modern_layout_are_available_without_losing_fiscal_sections(): void
    {
        $design = CompanyPosDocumentTemplateController::defaults('FISCAL_INVOICE');
        $this->assertSame(4, $design['renderer_version']);
        $this->assertCount(12, $design['sections']);
        $this->assertContains('qr', $design['sections']);
        $this->assertContains('fiscal', $design['sections']);
        $this->assertFalse($design['qr_enabled']);
        $this->assertSame('', $design['qr_url']);
    }
}
