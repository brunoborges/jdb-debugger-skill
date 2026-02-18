package com.example;

import java.util.Map;

public class ConsoleAppTest {

    public static void main(String[] args) {

        Map<String, Integer> discounts = Map.of(
                "BASIC", 5,
                "PREMIUM", 20,
                "VIP", 30
        );

        if (args.length == 0) {
            System.out.println("Usage: java App <TIER>");
            return;
        }

        String tier = args[0];

        Integer discount = discounts.get(tier);

        if (discount == null) {
            discount = 0;
        }

        System.out.println("Discount = " + discount + "%");
    }
}
