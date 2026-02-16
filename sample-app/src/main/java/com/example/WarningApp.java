package com.example;

import javax.swing.*;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.util.ArrayList;
import java.util.List;

/**
 * Sample Swing application with intentional bugs for testing the JDB debugger skill.
 *
 * Known bugs (for debugging practice):
 * 1. NullPointerException when input is empty (line ~70)
 * 2. Off-by-one error in warning counter display (line ~85)
 * 3. Memory leak — warnings list never cleared (line ~50)
 * 4. StringIndexOutOfBoundsException when input is shorter than 3 chars (line ~76)
 */
public class WarningApp extends JFrame {

    private JTextField inputField;
    private JButton warnButton;
    private JButton clearButton;
    private JLabel counterLabel;
    private List<String> warningHistory;
    private int warningCount;

    public WarningApp() {
        super("Warning App");
        warningHistory = new ArrayList<>();
        warningCount = 0;
        initUI();
    }

    private void initUI() {
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(450, 180);
        setLocationRelativeTo(null);

        JPanel panel = new JPanel(new BorderLayout(10, 10));
        panel.setBorder(BorderFactory.createEmptyBorder(15, 15, 15, 15));

        // Input row
        JPanel inputPanel = new JPanel(new BorderLayout(8, 0));
        inputField = new JTextField();
        inputField.setFont(new Font("SansSerif", Font.PLAIN, 14));
        inputPanel.add(new JLabel("Message: "), BorderLayout.WEST);
        inputPanel.add(inputField, BorderLayout.CENTER);

        // Button row
        JPanel buttonPanel = new JPanel(new FlowLayout(FlowLayout.CENTER, 10, 0));
        warnButton = new JButton("Show Warning");
        clearButton = new JButton("Clear History");
        counterLabel = new JLabel("Warnings shown: 0");
        buttonPanel.add(warnButton);
        buttonPanel.add(clearButton);
        buttonPanel.add(counterLabel);

        panel.add(inputPanel, BorderLayout.NORTH);
        panel.add(buttonPanel, BorderLayout.CENTER);

        setContentPane(panel);

        warnButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                showWarning();
            }
        });

        clearButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {
                clearHistory();
            }
        });
    }

    private void showWarning() {
        String text = inputField.getText();

        // BUG 1: No null/empty check — processMessage will NPE on null
        String processed = processMessage(text);

        // BUG 4: Substring without bounds check — crashes if input < 3 chars
        String preview = text.substring(0, 3);
        System.out.println("Preview: " + preview);

        warningHistory.add(processed);
        warningCount++;

        // BUG 2: Off-by-one — displays count - 1 instead of count
        counterLabel.setText("Warnings shown: " + (warningCount - 1));

        JOptionPane.showMessageDialog(
                this,
                processed,
                "Warning #" + warningCount,
                JOptionPane.WARNING_MESSAGE
        );
    }

    private String processMessage(String message) {
        // BUG 1: This will throw NPE if message is null
        String trimmed = message.trim();

        if (trimmed.isEmpty()) {
            // BUG 1 continued: returns null instead of a default message
            return null;
        }

        return "⚠ " + trimmed.toUpperCase() + " ⚠";
    }

    private void clearHistory() {
        // BUG 3: Sets list to null instead of clearing it — next add() will NPE
        warningHistory = null;
        warningCount = 0;
        counterLabel.setText("Warnings shown: 0");
        System.out.println("History cleared (or is it?)");
    }

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> {
            WarningApp app = new WarningApp();
            app.setVisible(true);
        });
    }
}
