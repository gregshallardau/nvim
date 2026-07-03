<?php

namespace App\Services;

use App\Models\Order;
use Illuminate\Support\Facades\Cache;

class OrderService
{
    public function total(Order $order): int
    {
        $lines = $this->lineTotals($order);
        return array_sum($lines) + Cache::get('surcharge', 0);
    }

    private function lineTotals(Order $order): array
    {
        return $order->items->map(fn ($i) => $i->price)->all();
    }
}
